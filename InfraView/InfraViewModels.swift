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

// ===== ViewerViewModel.swift =====
// InfraViewModels.swift

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var zoom: CGFloat = 1
    @Published var fitToScreen = false
    @Published var currentImage: NSImage?
    @Published var loadingError: String?

    private var baseImage: NSImage?
    private var currentURL: URL?
    
    private let repo: ImageRepository
    private let cache: ImageCache
    private let preloader: ImagePreloader
    private let sizer: WindowSizer

    init(repo: ImageRepository, cache: ImageCache, preloader: ImagePreloader, sizer: WindowSizer) {
        self.repo = repo; self.cache = cache; self.preloader = preloader; self.sizer = sizer
    }

    // 统一驱动：新图 / 切换 Fit / 改 Zoom 都走这里
    enum Reason: Equatable { case newImage, fitToggle(Bool), zoom(CGFloat) }

    func drive(reason: Reason, mode: FitMode, window: NSWindow) {
        guard let img = currentImage else { return }
        
        // 先基于窗口内容区域算好 fit 比例
        var fitScaleAccurate = sizer.accurateFitScale(for: img, in: window)

        switch reason {
        case .newImage:
            // 初始状态
            switch mode {
            case .doNotFit:           fitToScreen = false; zoom = 1
            case .fitWindowToImage:   fitToScreen = false; zoom = 1
            case .fitImageToWindow:   fitToScreen = true;  zoom = fitScaleAccurate // 1
            case .fitOnlyBigToWindow:
                if isBigInCurrentWindow(img, window: window) {
                    fitToScreen = true; zoom = fitScaleAccurate // 1
                } else { fitToScreen = false; zoom = 1 }
            case .fitOnlyBigToDesktop:
                if sizer.isBigOnDesktop(img, window: window) {
                    fitToScreen = true; zoom = fitScaleAccurate // 1
                } else { fitToScreen = false; zoom = 1 }
            }
        // TODO: remove fitToggle
        case .fitToggle(let on):
            fitToScreen = on
            // 用 fitScaleAccurate?
            if on { zoom = 1 } // 进入 fit 模式时，zoom 统一到 1
        
        case .zoom(let v):
            fitToScreen = false
            zoom = clamp(v, 0.25...10)
        }

        // 统一计算目标内容尺寸并调窗口（把所有模式分支写在一个地方）
        let (targetSize, shouldResize, aware) = desiredContentSize(for: img, mode: mode, window: window)
        var doResize = shouldResize
        if (mode == .fitImageToWindow || mode == .fitOnlyBigToWindow), reason != .newImage {
            doResize = false
        }
        if doResize {
            sizer.resizeWindow(toContent: targetSize, mode: aware ? mode : .fitOnlyBigToDesktop)
            if fitToScreen {
                fitScaleAccurate = sizer.accurateFitScale(for: img, in: window)
                zoom = fitScaleAccurate
            }
        }
        // ✅ 2) .fitOnlyBigToDesktop 的第二步：回退到精确缩放（只在 newImage 时执行）
        if mode == .fitOnlyBigToDesktop,
           reason == .newImage,
           sizer.isBigOnDesktop(img, window: window) {
             let fitScaleAccurate = sizer.accurateFitScale(for: img, in: window)
             fitToScreen = false
             zoom = fitScaleAccurate
             // 这里不用再 resize 了，保持刚刚收敛的窗口即可
        }

        // 百分比回调
        //if fitToScreen {
        //    zoom = sizer.accurateFitScale(for: img, in: window)
        //}
    }

    // 载入/切图：只负责拿图，其余交给 drive(.newImage)
    func show(index: Int, in urls: [URL], fitMode: FitMode, window: NSWindow) {
        guard urls.indices.contains(index) else { return }
        let url = urls[index]
        currentURL = url  // used for persistent rotate
        loadingError = nil
        currentImage = nil   // 清空旧图，避免误用

        // 1) 先用缓存（同步路径）
        if let cached = cache.get(url) {
            baseImage = cached
            let q = RotationStore.shared.get(for: url)
            currentImage = (q == 0) ? cached : rotate(cached, quarterTurns: q)
            drive(reason: .newImage, mode: fitMode, window: window)
        } else {
            // 2) 没缓存：异步加载，回主线程后再应用旋转并 drive
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let result = try? self.repo.load(at: url)
                await MainActor.run {
                    // 若期间用户已切到别的图，避免回写
                    guard self.currentURL == url else { return }
                    if let (img, _) = result {
                        self.baseImage = img
                        self.cache.set(url, img)
                        let q = RotationStore.shared.get(for: url)
                        self.currentImage = (q == 0) ? img : rotate(img, quarterTurns: q)
                        self.drive(reason: .newImage, mode: fitMode, window: window)
                    } else {
                        self.loadingError = "Unsupported image format."
                    }
                }
            }
        }
        preloader.preload(adjacentOf: index, in: urls)
    }

    // 统一把“要多大”和“是否滚动条感知”算出来
    private func desiredContentSize(for img: NSImage, mode: FitMode, window: NSWindow) -> (CGSize, Bool, Bool) {
        // (targetSize, shouldResizeWindow, scrollbarAware
        switch mode {
        case .fitImageToWindow:
            return (sizer.fittedContentSize(for: img, in: window), false, true)

        case .fitOnlyBigToWindow:
            if isBigInCurrentWindow(img, window: window) {
                return (sizer.fittedContentSize(for: img, in: window), false, true)
            } else {
                // 小图 → 用 1x 大小（带屏幕上限）
                return (scaledContentSize(for: img, scale: 1), false, true)
            }
        case .fitOnlyBigToDesktop:
            let sz = alignedScaledSizeToBacking(img, scale: zoom, window: window)
            return (sz, true, false)
        case .fitWindowToImage:
            // 不启用 fit，按当前 zoom（初始 1x）并限幅到屏幕
            let sz = alignedScaledSizeToBacking(img, scale: zoom, window: window)
            return (sz, true, true)
            //return (scaledContentSize(for: img, scale: zoom), true, false)

        case .doNotFit:
            // 同上，但明确不自动调整：也给窗口一个合理大小（你也可以改为保持窗口不变）
            return (scaledContentSize(for: img, scale: zoom), false, true)
        }
    }
    private func isBigInCurrentWindow(_ img: NSImage, window: NSWindow) -> Bool {
        let natural = naturalPointSize(img)
        let layout = window.contentLayoutRect.size   // 当前窗口内容区（考虑了工具栏等）
        return natural.width > layout.width || natural.height > layout.height
    }
    private func alignedScaledSizeToBacking(_ img: NSImage, scale: CGFloat, window: NSWindow) -> CGSize {
        let base = naturalPointSize(img)
        let w = base.width  * scale
        let h = base.height * scale
        let s = window.backingScaleFactor
        // ZoomableImage 用的是 floor，所以这里也用 floor，避免窗口比内容“略大”
        return CGSize(width: floor(w * s) / s,
                      height: floor(h * s) / s)
    }
    
    func rotateCurrentImage(fitMode: FitMode, by q: Int, window: NSWindow) {
        guard let url = currentURL, let base = baseImage else { return }
        
        let oldQ = RotationStore.shared.get(for: url)
        let newQ = ((oldQ + q) % 4 + 4) % 4
        RotationStore.shared.set(newQ, for: url)
        
        currentImage = (newQ == 0) ? base : rotate(base, quarterTurns: newQ)
        
        drive(reason: .fitToggle(true), mode: fitMode, window: window)
        //onScaleChanged?(Int(round(zoom * 100)))
    }
}
