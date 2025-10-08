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

