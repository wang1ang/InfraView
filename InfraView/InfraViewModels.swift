// InfraViewModels.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

@MainActor
final class ImageStore: ObservableObject {
    @Published var imageURLs: [URL] = []
    @Published var selection: Int? = nil

    // ✅ 持有当前这一批“用户选中的入口”的作用域（文件或其父目录/文件夹）
    private var heldSecurityScopedRoots: [URL] = []

    private func releaseHeldScopes() {
        for u in heldSecurityScopedRoots { u.stopAccessingSecurityScopedResource() }
        heldSecurityScopedRoots.removeAll()
    }

    private func requestDirectoryScope(for parent: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = parent
        panel.prompt = "Allow"
        panel.message = "To browse images in this folder, please grant one-time access to the folder."

        // ✅ 同步阻塞直到用户操作完成
        let resp = panel.runModal()
        return (resp == .OK) ? panel.urls.first : nil

    }
    

    func load(urls: [URL]) {
        // 每次用户重新选择前，释放上一批作用域
        releaseHeldScopes()

        let fm = FileManager.default
        let exts: Set<String> = ["png","jpg","jpeg","gif","tiff","bmp","heic","webp"]
        var collected: [URL] = []
        var urlsToProcess = urls
        var initialSelectionURL: URL? = nil

        if urls.count == 1, let first = urls.first {
            // 至少保证这个文件可读
            if first.startAccessingSecurityScopedResource() { heldSecurityScopedRoots.append(first) }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: first.path, isDirectory: &isDir), !isDir.boolValue {
                let parent = first.deletingLastPathComponent()

                // 1) 先试图从书签恢复目录作用域（无 UI）
                var grantedDir: URL? = BookmarkStore.resolve(matching: parent)
                if grantedDir == nil {
                    // 2) 恢复失败，再弹一次目录选择（仅第一次）
                    grantedDir = requestDirectoryScope(for: parent)
                    if let dir = grantedDir {
                        BookmarkStore.save(url: dir)  // 持久化，下次就无需再弹
                    }
                }

                // 如果我们最终拿到了目录作用域，就持有它并用来枚举
                if let dir = grantedDir, dir.startAccessingSecurityScopedResource() {
                    heldSecurityScopedRoots.append(dir)
                    urlsToProcess = [parent]
                } else {
                    // 用户拒绝/未命中书签：只能浏览这一个文件
                    urlsToProcess = [first]
                }
                initialSelectionURL = first
            }
        }
        // ✅ 多选或选文件夹：对每个“入口”持有作用域直到下次 load
        for url in urlsToProcess {
            if url.startAccessingSecurityScopedResource() { heldSecurityScopedRoots.append(url) }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                do {
                    let files = try fm.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    )
                    for f in files {
                        let vals = try? f.resourceValues(forKeys: [.isRegularFileKey])
                        if vals?.isRegularFile == true && exts.contains(f.pathExtension.lowercased()) {
                            collected.append(f)
                        }
                    }
                } catch {
                    print("Could not read contents of directory: \(url.path), error: \(error)")
                }
            } else if exts.contains(url.pathExtension.lowercased()) {
                collected.append(url)
            }
        }

        let uniqueURLs = Array(Set(collected))
        imageURLs = uniqueURLs.sorted { lhs, rhs in
            let n = lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent)
            if n != .orderedSame { return n == .orderedAscending }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }

        if let u = initialSelectionURL, let idx = imageURLs.firstIndex(of: u) {
            selection = idx
        } else {
            selection = imageURLs.isEmpty ? nil : 0
        }
    }

    func delete(at index: Int) throws {
        guard imageURLs.indices.contains(index) else { return }
        let url = imageURLs[index]
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        imageURLs.remove(at: index)
    }
}

// ===== ViewerViewModel.swift (append inside InfraViewModels.swift) =====
@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var zoom: CGFloat = 1
    @Published var fitToScreen: Bool = false
    @Published var currentImage: NSImage?
    @Published var loadingError: String?

    // scale 变化时回调（用于工具栏百分比显示）
    var onScaleChanged: ((Int) -> Void)?

    private let repo: ImageRepository
    private let cache: ImageCache
    private let preloader: ImagePreloader
    private let sizer: WindowSizer

    init(repo: ImageRepository, cache: ImageCache, preloader: ImagePreloader, sizer: WindowSizer) {
        self.repo = repo
        self.cache = cache
        self.preloader = preloader
        self.sizer = sizer
    }

    func show(index: Int, in urls: [URL], fitMode: FitMode, window: NSWindow) {
        guard urls.indices.contains(index) else { return }
        let url = urls[index]

        // 命中缓存
        if let cached = cache.get(url) {
            currentImage = cached
            loadingError = nil
            applyInitialFit(for: cached, mode: fitMode, window: window)
        } else {
            currentImage = nil
            loadingError = nil
            Task.detached(priority: .userInitiated) {
                let result = try? self.repo.load(at: url)
                await MainActor.run {
                    if let (img, _) = result {
                        self.currentImage = img
                        self.cache.set(url, img)
                        self.applyInitialFit(for: img, mode: fitMode, window: window)
                    } else {
                        self.loadingError = "Unsupported image format."
                    }
                }
            }
        }

        // 预加载相邻
        preloader.preload(adjacentOf: index, in: urls)
    }

    func handleZoomChanged(_ newZoom: CGFloat, window: NSWindow) {
        zoom = newZoom
        fitToScreen = false
        notifyScale(window: window)
    }

    func handleFitToggled(_ newFit: Bool, window: NSWindow) {
        fitToScreen = newFit
        notifyScale(window: window)
    }

    // MARK: - Private
    private func applyInitialFit(for img: NSImage, mode: FitMode, window: NSWindow) {
        switch mode {
        case .fitWindowToImage:
            fitToScreen = false; zoom = 1

        case .fitImageToWindow:
            fitToScreen = true;  zoom = 1
            sizer.resizeWindow(toContent: sizer.fittedContentSize(for: img, in: window), mode: mode)

        case .fitOnlyBigToWindow:
            let big = sizer.isBigOnDesktop(img, window: window)
            fitToScreen = big; zoom = 1
            if big {
                sizer.resizeWindow(toContent: sizer.fittedContentSize(for: img, in: window), mode: mode)
            }

        case .fitOnlyBigToDesktop:
            if sizer.isBigOnDesktop(img, window: window) {
                // 先用 Fit 驱动一次窗口收敛
                fitToScreen = true; zoom = 1
                sizer.resizeWindow(toContent: sizer.fittedContentSize(for: img, in: window), mode: mode)
                // 再回退到“精确 scale”
                let s = sizer.accurateFitScale(for: img, in: window)
                fitToScreen = false; zoom = s
            } else {
                fitToScreen = false; zoom = 1
            }

        case .doNotFit:
            fitToScreen = false; zoom = 1
        }

        notifyScale(window: window)
    }

    private func notifyScale(window: NSWindow) {
        guard let img = currentImage else { return }
        let scale: CGFloat = fitToScreen ? sizer.accurateFitScale(for: img, in: window) : zoom
        onScaleChanged?(Int((scale * 100).rounded()))
    }
}
