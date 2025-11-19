//
//  ImageStore.swift
//  InfraView
//
//  Created by 王洋 on 8/11/2025.
//
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
    
    private func isSupportedImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return false }

        // 特判 webp（你已经有 webPCompat了）
        if ext == "webp" { return true }

        // 统一交给 UTType 判断是否属于 image（包含 rawImage）
        if let type = UTType(filenameExtension: ext) {
            return type.conforms(to: .image)
        }
        return false
    }
    func load(urls: [URL]) {
        // 每次用户重新选择前，释放上一批作用域
        releaseHeldScopes()

        let fm = FileManager.default
        //let exts: Set<String> = ["png","jpg","jpeg","gif","tiff","bmp","heic","webp"]
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
                        if vals?.isRegularFile == true && isSupportedImageURL(f) {
                            collected.append(f)
                        }
                    }
                } catch {
                    print("Could not read contents of directory: \(url.path), error: \(error)")
                }
            } else if isSupportedImageURL(url) {
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


// MARK: - ImageRepository（把解码独立）
protocol ImageRepository {
    func load(at url: URL) throws -> (cgImage: CGImage, pixelSize: CGSize)
}

final class ImageRepositoryImpl: ImageRepository {
    func load(at url: URL) throws -> (cgImage: CGImage, pixelSize: CGSize) {
        // 直接使用你现有 decodeCGImageApplyingOrientation/loadCGForURL 的逻辑拼装
        let (cgOpt, px, err) = loadCGForURL(url)      // 从下方 Helpers 复用
        guard let cg = cgOpt else { throw NSError(domain: "InfraView", code: 2, userInfo: [NSLocalizedDescriptionKey: err ?? "Unsupported"]) }
        return (cg, px)
    }
}

// MARK: - 轻量 LRU 缓存 + 预加载
struct LoadedImage {
    let image: NSImage
    let pixelSize: CGSize
}

final class ImageCache {
    // ⚠️ 约定：仅在主线程读写（调用方已在 MainActor 切回主线程）
    private var dict: [URL:LoadedImage] = [:]
    private var order: [URL] = []
    private let cap: Int
    init(capacity: Int = 8) { self.cap = capacity }
    func get(_ u: URL) -> LoadedImage? { dict[u] }
    func set(_ u: URL, _ img: LoadedImage) {
        dict[u] = img; order.removeAll{ $0==u }; order.append(u)
        while order.count > cap { dict.removeValue(forKey: order.removeFirst()) }
    }
    func trim(keeping set: Set<URL>) {
        order.removeAll{ !set.contains($0) }
        dict = dict.filter{ set.contains($0.key) }
    }
}

final class ImagePreloader {
    private let repo: ImageRepository, cache: ImageCache
    init(repo: ImageRepository, cache: ImageCache) { self.repo = repo; self.cache = cache }
    func preload(adjacentOf idx: Int, in urls: [URL]) {
        guard !urls.isEmpty else { return }
        for i in [ (idx-1+urls.count)%urls.count, (idx+1)%urls.count ] {
            let u = urls[i]
            if cache.get(u) == nil {
                DispatchQueue.global(qos: .background).async {
                    if let (cg, px) = try? self.repo.load(at: u) {
                        let nsImage = NSImage(cgImage: cg, size: px)
                        DispatchQueue.main.async { self.cache.set(u, LoadedImage(image: nsImage, pixelSize: px)) }
                    }
                }
            }
        }
    }
}
