// InfraView - Enhanced version (macOS, single-file, no sidebar)
// Features: open images/folders, ←/→ browse same folder, Delete to trash,
// default 100% per image, slider + preset zoom with live percent,
// precise window auto-sizing (scrollbar-aware), image preloading, robust errors.

import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit
import ImageIO

// MARK: - Model

enum FitMode: String, CaseIterable {
    case fitWindowToImage = "Fit window to image"
    case fitImageToWindow = "Fit image to window"
    case fitOnlyBigToWindow = "Fit only big images to window"
    case fitOnlyBigToDesktop = "Fit only big images to desktop"
    case doNotFit = "Do not fit anything"
}
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
    
    private enum BookmarkStore {
        private static let defaultsKey = "ScopedBookmarks"

        static func save(url: URL) {
            do {
                let data = try url.bookmarkData(options: [.withSecurityScope],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
                var dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
                let key = url.standardizedFileURL.path
                dict[key] = data
                UserDefaults.standard.set(dict, forKey: defaultsKey)
            } catch {
                print("Save bookmark failed:", error)
            }
        }

        /// 尝试命中精确目录；否则做“最长祖先目录”的匹配
        static func resolve(matching parent: URL) -> URL? {
            guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] else {
                return nil
            }
            let parentPath = parent.standardizedFileURL.path

            // 1) 精确命中
            if let exact = dict[parentPath] {
                var stale = false
                if let u = try? URL(resolvingBookmarkData: exact,
                                    options: [.withSecurityScope, .withoutUI],
                                    relativeTo: nil,
                                    bookmarkDataIsStale: &stale),
                   !stale {
                    return u
                }
            }

            // 2) 祖先匹配（优先更长的祖先路径）
            let sorted = dict.keys.sorted { $0.count > $1.count }
            for k in sorted {
                if parentPath == k || parentPath.hasPrefix(k + "/") {
                    if let data = dict[k] {
                        var stale = false
                        if let u = try? URL(resolvingBookmarkData: data,
                                            options: [.withSecurityScope, .withoutUI],
                                            relativeTo: nil,
                                            bookmarkDataIsStale: &stale),
                           !stale {
                            return u
                        }
                    }
                }
            }
            return nil
        }
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



// MARK: - ContentView

struct ContentView: View {
    @StateObject private var store = ImageStore()
    @State private var zoom: CGFloat = 1
    @State private var fitToScreen: Bool = false
    @State private var showImporter = false
    @State private var scalePercent: Int = 100
    @State private var fitMode: FitMode = .fitWindowToImage
    @State private var toolbarWasVisible = true
    private let zoomPresets: [CGFloat] = [0.25, 0.33, 0.5, 0.66, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 5.0]

    var body: some View {
        GeometryReader { geometry in
            Viewer(store: store, zoom: $zoom, fitToScreen: $fitToScreen, fitMode: fitMode) { p in
                scalePercent = p
            }
        }
        .toolbar {
            compactToolbar
        }
        //.controlSize(.mini)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image, .webPCompat, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { store.load(urls: urls) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraNext)) { _ in next() }
        .onReceive(NotificationCenter.default.publisher(for: .infraPrev)) { _ in previous() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            if let w = NSApp.keyWindow {
                toolbarWasVisible = w.toolbar?.isVisible ?? true
                w.toolbar?.isVisible = false
                w.titleVisibility = .hidden
                w.titlebarAppearsTransparent = true
                if #available(macOS 11.0, *) {
                    w.titlebarSeparatorStyle = .none
                }
                NSCursor.setHiddenUntilMouseMoves(true) // 鼠标静止时自动隐藏
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            if let w = NSApp.keyWindow {
                w.toolbar?.isVisible = toolbarWasVisible
                w.titleVisibility = .visible
                w.titlebarAppearsTransparent = false
                if #available(macOS 11.0, *) {
                    w.titlebarSeparatorStyle = .automatic
                }
            }
        }
        .onDrop(of: [UTType.fileURL, .image], isTargeted: nil) { providers in
            // 如果什么都处理不了，返回 false，避免吞掉事件
            let canHandle = providers.contains {
                $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
                $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            }
            guard canHandle else { return false }
            
            Task.detached(priority: .userInitiated) {
                var urls: [URL] = []
                
                // 逐个 provider 解包（可能返回 URL / NSURL / Data）
                for p in providers {
                    if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        if let url = await loadItemURL(provider: p, type: UTType.fileURL) {
                            urls.append(url)
                            continue
                        }
                    }
                    if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        if let url = await loadItemURL(provider: p, type: .image) {
                            urls.append(url)
                        }
                    }
                }
                
                guard !urls.isEmpty else { return }
                // ⬇️⬇️⬇️ 关键：回到主线程调用 store.load
                await MainActor.run {
                    // ① 激活 App（把它带到前台）
                    NSApp.activate(ignoringOtherApps: true)

                    // ② 让当前可见窗口成为 key & 置前
                    if let win = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
                        win.makeKeyAndOrderFront(nil)
                    }

                    // ③ 再去加载（会触发你的 resetForNewImage → 自适应尺寸）
                    store.load(urls: urls)
                }

            }
            
            return true
        }
    }

    var compactToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button { showImporter = true } label: { Image(systemName: "folder") }
                .keyboardShortcut("o", modifiers: [.command])

            Menu {
                ForEach(FitMode.allCases, id: \.self) { mode in
                    Button(action: { fitMode = mode }) {
                        HStack { Text(mode.rawValue); Spacer(); if fitMode == mode { Image(systemName: "checkmark") } }
                    }
                }
            } label: { Image(systemName: fitToScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }

            Menu(content: {
                Slider(value: Binding(get: { zoom }, set: { v in fitToScreen = false; zoom = v }), in: 0.25...5)
                Divider(); zoomMenuContent
            }, label: { Text("\(scalePercent)%") })

            Button { previous() } label: { Image(systemName: "chevron.left") }.keyboardShortcut(.leftArrow, modifiers: [])
            Button { next() } label: { Image(systemName: "chevron.right") }.keyboardShortcut(.rightArrow, modifiers: [])
            Button { deleteCurrent() } label: { Image(systemName: "trash") }
                .keyboardShortcut(.delete, modifiers: [])
                .keyboardShortcut(.delete, modifiers: [.command])
                .keyboardShortcut(.deleteForward, modifiers: [])
        }
    }

    @ViewBuilder
    var zoomMenuContent: some View {
        Button("Fit") { fitToScreen = true }
        Divider()
        ForEach(zoomPresets, id: \.self) { z in Button("\(Int(z * 100))%") { fitToScreen = false; zoom = z } }
    }

    private func next() { guard let sel = store.selection, !store.imageURLs.isEmpty else { return }; store.selection = (sel + 1) % store.imageURLs.count }
    private func previous() { guard let sel = store.selection, !store.imageURLs.isEmpty else { return }; store.selection = (sel - 1 + store.imageURLs.count) % store.imageURLs.count }
    private func deleteCurrent() {
        guard let idx = store.selection, !store.imageURLs.isEmpty else { return }
        do {
            try store.delete(at: idx)
            store.selection = store.imageURLs.isEmpty ? nil : min(idx, store.imageURLs.count - 1)
        } catch { print("Delete failed:", error) }
    }
}

// MARK: - Viewer

@MainActor
struct Viewer: View {
    @ObservedObject var store: ImageStore
    @Binding var zoom: CGFloat
    @Binding var fitToScreen: Bool
    let fitMode: FitMode
    var onScaleChanged: (Int) -> Void

    @State private var currentImage: NSImage? = nil
    @State private var loadingError: String? = nil
    @State private var isLoading: Bool = false
    @State private var preloadedImages: [URL: NSImage] = [:]
    @State private var preloadOrder: [URL] = []
    private let preloadCapacity = 8

    private func touchPreloadOrder(_ url: URL) {
        preloadOrder.removeAll { $0 == url }
        preloadOrder.append(url)
        while preloadOrder.count > preloadCapacity {
            let evict = preloadOrder.removeFirst()
            preloadedImages.removeValue(forKey: evict)
        }
    }
    
    private func currentWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
    }

    @inline(__always)
    private func maybeResizeWindow(for img: NSImage) {
        switch fitMode {
        case .fitWindowToImage:
            resizeOnceForCurrentFit(img)
        case .fitOnlyBigToDesktop:
            resizeOnceForCurrentFit(img)
            //let size = targetSize(for: img)
            //resizeWindowToContentSize(size, scrollbarAware: false)
        default:
            break  // .fitOnlyBigToWindow & .fitImageToWindow & .doNotFit 都不动窗口
        }
    }

    var body: some View {
        if let index = store.selection, index < store.imageURLs.count {
            let url = store.imageURLs[index]
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().progressViewStyle(CircularProgressViewStyle()).scaleEffect(1.2)
                        Text("Loading...").font(.headline).foregroundColor(.secondary)
                    }
                } else if let err = loadingError {
                    Placeholder(title: "Failed to load", systemName: "exclamationmark.triangle", text: err)
                } else if let img = currentImage {
                    ZoomableImage(
                        image: img,
                        zoom: $zoom,
                        fitToScreen: $fitToScreen,
                        fitMode: fitMode,
                        onScaleChanged: onScaleChanged,
                        onLayoutChange: { needScroll, contentSize in
                            guard needScroll else { return }
                            switch fitMode {
                            case .fitOnlyBigToDesktop, .fitImageToWindow, .fitWindowToImage:
                                //resizeWindowToContentSize(contentSize)
                                break
                            case .fitOnlyBigToWindow, .doNotFit:
                                break
                            }
                        }
                    )
                    .id(url)
                    .onChange(of: fitToScreen) { _, _ in
                        if let img = currentImage { maybeResizeWindow(for: img)}
                    }
                    .onChange(of: zoom) { _, newZoom in
                        if !fitToScreen && fitMode == .fitWindowToImage {
                            //resizeWindowToContentSize(scaledContentSize(for: img, scale: newZoom))
                        }
                    }
                    .navigationTitle(url.lastPathComponent)
                } else {
                    Placeholder(title: "No image", systemName: "photo", text: url.lastPathComponent)
                }
            }
            .onAppear(perform: loadImageForSelection)
            .onChange(of: store.selection) { _, _ in loadImageForSelection(); preloadAdjacentImages() }
            .onChange(of: store.imageURLs) { _, newList in
                let keep = Set(newList)
                preloadOrder.removeAll { !keep.contains($0) }
                preloadedImages = preloadedImages.filter { keep.contains($0.key) }
            }
            .onChange(of: fitMode) { _, _ in if let img = currentImage {
                resetForNewImage(img)
            } }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                if let img = currentImage { resetForNewImage(img) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                if let img = currentImage { resetForNewImage(img) }
            }
        } else {
            Placeholder(title: "No Selection", systemName: "rectangle.dashed", text: "Open an image (⌘O)")
        }
    }

    @State private var loadToken: UUID = .init()
    private func loadImageForSelection() {
        guard let index = store.selection, index < store.imageURLs.count else {
            currentImage = nil; loadingError = nil; return
        }
        let url = store.imageURLs[index]

        // 命中新缓存
        if let cached = preloadedImages[url] {
            currentImage = cached; loadingError = nil; isLoading = false
            resetForNewImage(cached)
            return
        }

        isLoading = true
        loadingError = nil
        currentImage = nil
        let token = UUID()
        loadToken = token

        // 后台：只做一次 CGImage 解码（带安全作用域）
        DispatchQueue.global(qos: .userInitiated).async {
            let (cgOpt, pixelSize, err) = loadCGForURL(url)

            // 主线程：根据当前屏幕 scale 计算 pointSize，创建 NSImage，并更新 UI
            DispatchQueue.main.async {
                guard self.loadToken == token else { return }
                self.isLoading = false

                guard let cg = cgOpt else {
                    self.currentImage = nil
                    self.loadingError = err ?? "Unsupported image format."
                    return
                }

                // 在主线程获取 scale 更稳（涉及 NSApp/NSScreen）
                let scale = displayScaleFactor()
                let pointSize = NSSize(width: pixelSize.width / scale,
                                       height: pixelSize.height / scale)

                let img = NSImage(cgImage: cg, size: pointSize)
                self.currentImage = img
                self.loadingError = nil
                self.resetForNewImage(img)
                self.preloadedImages[url] = img
                self.touchPreloadOrder(url)
            }
        }
    }


    private func preloadAdjacentImages() {
        guard let current = store.selection, !store.imageURLs.isEmpty else { return }
        let urls = store.imageURLs
        let candidates = [
            (current - 1 + urls.count) % urls.count,
            (current + 1) % urls.count
        ].map { urls[$0] }

        for u in candidates where preloadedImages[u] == nil {
            DispatchQueue.global(qos: .background).async {
                let (cgOpt, pixelSize, _) = loadCGForURL(u)
                guard let cg = cgOpt else { return }
                DispatchQueue.main.async {
                    // 主线程计算 scale & 创建 NSImage
                    let scale = displayScaleFactor()
                    let pointSize = NSSize(width: pixelSize.width / scale,
                                           height: pixelSize.height / scale)
                    let img = NSImage(cgImage: cg, size: pointSize)
                    preloadedImages[u] = img
                    touchPreloadOrder(u) // LRU 维护（主线程）
                }
            }
        }
    }

    private func isBigOnThisDesktop(_ img: NSImage) -> Bool {
        guard let win = currentWindow() else { return false }
        let natural = naturalPointSize(img)
        let maxLayout = maxContentLayoutSizeInVisibleFrame(win)
        return natural.width > maxLayout.width || natural.height > maxLayout.height
    }
    private func fittedContentSizeAccurate(for image: NSImage) -> CGSize {
        guard let win = currentWindow() else { return naturalPointSize(image) }

        let base = naturalPointSize(image)
        // 最大 contentLayout 尺寸（无余量）
        var avail = maxContentLayoutSizeInVisibleFrame(win)

        // 估算 legacy 滚动条厚度
        let (vBar, hBar) = legacyScrollbarThickness()

        // 两轮迭代：先假设无条，再根据是否超出决定扣条宽，再重算
        for _ in 0..<2 {
            let scale = min(avail.width / max(base.width, 1),
                            avail.height / max(base.height, 1))
            let w = floor(base.width * scale)    // 用 floor，避免 1px 溢出导致出条
            let h = floor(base.height * scale)

            // 判断是否仍会出条（> avail），如果会，给出“扣条后的可用区”再来一轮
            let needV = h > avail.height
            let needH = w > avail.width
            var nextAvail = avail
            if needV { nextAvail.width  = max(0, nextAvail.width  - vBar) }
            if needH { nextAvail.height = max(0, nextAvail.height - hBar) }

            if nextAvail == avail {
                // 收敛
                return CGSize(width: w, height: h)
            }
            avail = nextAvail
        }

        // 兜底（一般到不了）
        let scale = min(avail.width / max(base.width, 1),
                        avail.height / max(base.height, 1))
        return CGSize(width: floor(base.width * scale),
                      height: floor(base.height * scale))
    }

    /// 返回：在当前屏幕的 visibleFrame 内，当前窗口样式下最大的 contentLayoutRect 尺寸
    private func maxContentLayoutSizeInVisibleFrame(_ window: NSWindow) -> CGSize {
        // 1) 屏幕的可用矩形（已扣除菜单栏/Dock）
        let vf = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // 2) 先求“contentRect 与 frameRect 的装饰差”
        //    用一个 100x100 的 dummy contentRect 反推出 frameRect，然后取差值
        let dummyContent = NSRect(x: 0, y: 0, width: 100, height: 100)
        let dummyFrame   = window.frameRect(forContentRect: dummyContent)
        let decoW = dummyFrame.width  - dummyContent.width
        let decoH = dummyFrame.height - dummyContent.height

        // 3) 当前窗口里 contentRect 与 contentLayoutRect 的差（工具栏等“吃掉”的区域）
        let currentFrame        = window.frame
        let currentContentRect  = window.contentRect(forFrameRect: currentFrame)
        let currentLayoutRect   = window.contentLayoutRect
        let layoutExtraW = max(0, currentContentRect.width  - currentLayoutRect.width)
        let layoutExtraH = max(0, currentContentRect.height - currentLayoutRect.height)

        // 4) 可容纳的最大 contentRect 尺寸 = visibleFrame 尺寸 - 窗口装饰
        let maxContentRectW = max(vf.width  - decoW, 0)
        let maxContentRectH = max(vf.height - decoH, 0)

        // 5) 再扣掉 contentRect → contentLayoutRect 的差，得到“最大 contentLayoutRect 尺寸”
        let maxLayoutW = max(maxContentRectW - layoutExtraW, 0)
        let maxLayoutH = max(maxContentRectH - layoutExtraH, 0)

        return CGSize(width: floor(maxLayoutW), height: floor(maxLayoutH))
    }
    private func accurateFitScale(for image: NSImage) -> CGFloat {
        guard let win = currentWindow() else { return 1 }
        let base = naturalPointSize(image)
        var avail = maxContentLayoutSizeInVisibleFrame(win)
        let (vBar, hBar) = legacyScrollbarThickness()
        for _ in 0..<2 {
            let s = min(avail.width / max(base.width, 1),
                        avail.height / max(base.height, 1))
            let w = floor(base.width * s), h = floor(base.height * s)
            let needV = h > avail.height
            let needH = w > avail.width
            var next = avail
            if needV { next.width  = max(0, next.width  - vBar) }
            if needH { next.height = max(0, next.height - hBar) }
            if next == avail { return s }
            avail = next
        }
        return min(avail.width / max(base.width, 1),
                   avail.height / max(base.height, 1))
    }

    private func resetForNewImage(_ img: NSImage) {
        let naturalSize = naturalPointSize(img)
        switch fitMode {
        case .fitWindowToImage:
            fitToScreen = false; zoom = 1;
        case .fitImageToWindow:
            fitToScreen = true; zoom = 1
        case .fitOnlyBigToWindow:
            let vf = (NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
            let padding: CGFloat = 100
            let maxW = max(vf.width - padding, 200)
            let maxH = max(vf.height - padding, 200)
            if naturalSize.width > maxW || naturalSize.height > maxH { fitToScreen = true; zoom = 1 }
            else { fitToScreen = false; zoom = 1;
            }
        case .fitOnlyBigToDesktop:
            if isBigOnThisDesktop(img) {
                DispatchQueue.main.async {
                    fitToScreen = true
                    zoom = 1
                    resizeOnceForCurrentFit(img)
                    
                    let s = accurateFitScale(for: img)
                    fitToScreen = false
                    zoom = s
                }
            }
            else { fitToScreen = false; zoom = 1 }
        case .doNotFit:
            fitToScreen = false; zoom = 1
        }

        // 更新百分比
        let vf = (NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
        let maxW = max(vf.width, 200)
        let maxH = max(vf.height, 200)
        let scale = computeScale(isFit: fitToScreen, baseW: naturalSize.width, baseH: naturalSize.height, maxW: maxW, maxH: maxH, zoom: zoom)
        onScaleChanged(Int(round(scale * 100)))
        maybeResizeWindow(for: img)
        // 拖拽/激活时窗口状态可能在下一轮 runloop 才稳定，补一次重试
        /*
        DispatchQueue.main.async {
            maybeResizeWindow(for: img)
        }*/
    }
    private func targetSize(for img: NSImage) -> CGSize {
        if fitToScreen {
            return fittedContentSizeAccurate(for: img)
        } else {
            switch fitMode {
            case .fitWindowToImage:
                // 自由缩放时，用当前 zoom 的内容尺寸
                return scaledContentSize(for: img, scale: zoom)
            case .fitImageToWindow:
                return fittedContentSizeAccurate(for: img)
            case .fitOnlyBigToWindow:
                return isBigOnThisDesktop(img) ? fittedContentSizeAccurate(for: img) : naturalPointSize(img)
            case .fitOnlyBigToDesktop:
                if isBigOnThisDesktop(img) {
                    return fittedContentSizeAccurate(for: img)
                } else {
                    return naturalPointSize(img)
                }
            case .doNotFit:
                return scaledContentSize(for: img, scale: zoom)
            }
        }
    }

    private func resizeOnceForCurrentFit(_ img: NSImage) {
        let desired = targetSize(for: img)
        let aware = (fitMode != .fitOnlyBigToDesktop)
        resizeWindowToContentSize(desired, scrollbarAware: aware)
    }
}

// MARK: - ZoomableImage
@inline(__always)
private func isAnimated(_ img: NSImage) -> Bool {
    img.representations.contains { ($0 as? NSBitmapImageRep)?.value(forProperty: .frameCount) as? Int ?? 0 > 1 }
}

struct ZoomableImage: View {
    let image: NSImage
    @Binding var zoom: CGFloat
    @Binding var fitToScreen: Bool
    let fitMode: FitMode
    var onScaleChanged: (Int) -> Void
    var onLayoutChange: ((Bool, CGSize) -> Void)? = nil // (needScroll, contentSize)

    @State private var baseZoom: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let maxW = max(proxy.size.width, 1)
            let maxH = max(proxy.size.height, 1)

            let naturalPt = naturalPointSize(image)
            let baseW = max(naturalPt.width, 1)
            let baseH = max(naturalPt.height, 1)
            let fitScale = min(maxW / baseW, maxH / baseH)
            let currentScale: CGFloat = fitToScreen ? fitScale : zoom

            let contentW = baseW * currentScale
            let contentH = baseH * currentScale
            
            let contentWf = floor(contentW)
            let contentHf = floor(contentH)
            
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let eps: CGFloat = 1.0 / scale
            let needScroll = (contentW - maxW) > eps || (contentH - maxH) > eps

            let view = Group {
                if needScroll {
                    ScrollView([.horizontal, .vertical]) {
                        if isAnimated(image){
                            AnimatedImageView(image: image)
                                .frame(width: contentWf, height: contentHf)
                        } else {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: contentWf, height: contentHf)
                        }
                    }
                } else {
                    if isAnimated(image) {
                        AnimatedImageView(image: image)
                            .frame(width: contentWf, height: contentHf)
                    } else {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: contentWf, height: contentHf)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .onAppear { baseZoom = zoom; onScaleChanged(Int(round(currentScale * 100))) }
            .onChange(of: fitToScreen) { _, newFit in
                let cs = computeScale(isFit: newFit, baseW: baseW, baseH: baseH, maxW: maxW, maxH: maxH, zoom: zoom)
                onScaleChanged(Int(round(cs * 100)))
            }
            .onChange(of: zoom) { _, newZoom in if !fitToScreen { onScaleChanged(Int(round(newZoom * 100))) }
                baseZoom = newZoom
            }
            .onChange(of: needScroll) { _, newNeed in onLayoutChange?(newNeed, CGSize(width: contentWf, height: contentHf)) }

            view
                .gesture(
                    MagnificationGesture()
                        .onChanged { v in fitToScreen = false; zoom = clamp(baseZoom * v, 0.25...5) }
                        .onEnded { _ in baseZoom = zoom }
                )
        }
        .background(Color.black)
    }
}

struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage
    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleNone
        v.animates = true
        v.image = image
        return v
    }
    func updateNSView(_ v: NSImageView, context: Context) {
        if v.image !== image { v.image = image }
        if v.animates == false { v.animates = true }
    }
}

// MARK: - Helpers
private func computeScale(isFit: Bool, baseW: CGFloat, baseH: CGFloat, maxW: CGFloat, maxH: CGFloat, zoom: CGFloat) -> CGFloat {
    let fitScale = min(maxW / baseW, maxH / baseH)
    return isFit ? fitScale : zoom
}

private func decodeCGImageApplyingOrientation(_ url: URL) -> (CGImage?, CGSize, String?) {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return (nil, .zero, "Unable to create image source.")
    }

    // 先取像素尺寸（不用创建整图，避免额外解码）
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as NSDictionary?
    let pxW = (props?[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
    let pxH = (props?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
    let maxDim = Int(max(pxW, pxH))

    // 用“缩略图”API但把目标尺寸设为原始最大边 + transform=true
    // 好处：ImageIO 会自动应用 EXIF 方向，不需要我们手写矩阵
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDim,
        kCGImageSourceCreateThumbnailWithTransform: true, // ✅ 应用 EXIF 方向
        kCGImageSourceShouldCache: false                  // 不提前缓存像素
    ]

    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
        return (nil, .zero, "Unsupported image format.")
    }
    // 注意：经方向修正后，像素宽高可能互换（例如 90° 旋转）
    let outSize = CGSize(width: cg.width, height: cg.height)
    return (cg, outSize, nil)
}
/*
private func loadImageWithError(url: URL) -> (NSImage?, String?) {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }

    guard FileManager.default.fileExists(atPath: url.path) else { return (nil, "File does not exist.") }
    guard FileManager.default.isReadableFile(atPath: url.path) else { return (nil, "File cannot be read.") }

    // 后台线程安全：先用 ImageIO 得到已修正方向的 CGImage + 像素尺寸
    let (cgOpt, pixelSize, err) = decodeCGImageApplyingOrientation(url)
    guard let cg = cgOpt else { return (nil, err ?? "Unsupported image format.") }

    // 为了和你现有 naturalPointSize/像素→点的逻辑一致，这里给 NSImage 设一个合理的 point 尺寸：
    // 取屏幕 scale（Retina=2），用 像素/scale 作为点尺寸；这样不会“看起来变大/变小”
    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
    let pointSize = NSSize(width: pixelSize.width / scale, height: pixelSize.height / scale)

    // 这一步最好在主线程创建；如果此函数在后台调用，外层回到主线程再包 NSImage
    let img = NSImage(cgImage: cg, size: pointSize)
    return (img, nil)
}
*/

private func displayScaleFactor() -> CGFloat {
    if let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
       let s = w.screen { return s.backingScaleFactor }
    return NSScreen.main?.backingScaleFactor ?? 2.0
}

private func pixelSize(_ img: NSImage) -> CGSize {
    var maxW = 0, maxH = 0
    for rep in img.representations where rep.pixelsWide > 0 && rep.pixelsHigh > 0 { maxW = max(maxW, rep.pixelsWide); maxH = max(maxH, rep.pixelsHigh) }
    if maxW == 0 || maxH == 0, let tiff = img.tiffRepresentation, let b = NSBitmapImageRep(data: tiff) {
        maxW = max(maxW, b.pixelsWide); maxH = max(maxH, b.pixelsHigh)
    }
    if maxW == 0 || maxH == 0 {
        let sf = displayScaleFactor(); let w = Int(img.size.width * sf), h = Int(img.size.height * sf)
        if w > 0 && h > 0 { maxW = w; maxH = h }
    }
    return CGSize(width: CGFloat(maxW), height: CGFloat(maxH))
}

private func naturalPointSize(_ img: NSImage) -> CGSize {
    let px = pixelSize(img); let sf = displayScaleFactor(); return CGSize(width: px.width / sf, height: px.height / sf)
}

private func legacyScrollbarThickness() -> (vertical: CGFloat, horizontal: CGFloat) {
    if NSScroller.preferredScrollerStyle == .overlay { return (0, 0) }
    let t = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy); return (vertical: t, horizontal: t)
}

private func scaledContentSize(for image: NSImage, scale: CGFloat) -> CGSize {
    let base = naturalPointSize(image)
    let vf = (NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
    let maxW = max(vf.width, 200)
    let maxH = max(vf.height, 200)
    return CGSize(width: ceil(min(base.width * scale, maxW)), height: ceil(min(base.height * scale, maxH)))
}

private func resizeWindowToContentSize(_ desiredContentSize: CGSize, scrollbarAware: Bool = true) {
    guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }

    // ✅ 关键补丁：先确保窗口不是 zoomed / fullScreen
    if window.styleMask.contains(.fullScreen) { return }      // 全屏下不处理

    let minW: CGFloat = 360, minH: CGFloat = 280
    var layoutW = max(ceil(desiredContentSize.width),  minW)
    var layoutH = max(ceil(desiredContentSize.height), minH)

    let currentFrame = window.frame
    let currentContentRect = window.contentRect(forFrameRect: currentFrame)
    let currentLayoutRect = window.contentLayoutRect
    let layoutExtraW = max(0, currentContentRect.width  - currentLayoutRect.width)
    let layoutExtraH = max(0, currentContentRect.height - currentLayoutRect.height)

    var contentW = layoutW + layoutExtraW
    var contentH = layoutH + layoutExtraH + (scrollbarAware ? 1 : 0)

    let (vBar, hBar) = legacyScrollbarThickness()
    let vf = (window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero

    let testContentRect = NSRect(x: 0, y: 0, width: 100, height: 100)
    let testFrame = window.frameRect(forContentRect: testContentRect)
    let decoW = testFrame.width  - testContentRect.width
    let decoH = testFrame.height - testContentRect.height
    var availW = max(vf.width  - decoW, minW)
    var availH = max(vf.height - decoH, minH)
    
    if scrollbarAware {
        var needV = contentH > availH
        var needH = contentW > availW
        for _ in 0..<2 {
            var nextAvailW = availW
            var nextAvailH = availH
            if needV { nextAvailW -= vBar }
            if needH { nextAvailH -= hBar }
            let nextNeedV = contentH > nextAvailH
            let nextNeedH = contentW > nextAvailW
            if nextNeedV == needV && nextNeedH == needH { break }
            needV = nextNeedV; needH = nextNeedH
            availW = nextAvailW; availH = nextAvailH
        }
        if needV { contentW += vBar }
        if needH { contentH += hBar }
    } else {
        contentW = min(contentW, availW)
        contentH = min(contentH, availH)
    }
    var targetFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH))
    let currentTop = window.frame.maxY
    targetFrame.origin.x = window.frame.origin.x
    targetFrame.origin.y = currentTop - targetFrame.height

    if let screen = window.screen {
        let vf2 = screen.visibleFrame
        if targetFrame.width  > vf2.width  { targetFrame.size.width  = vf2.width }
        if targetFrame.height > vf2.height { targetFrame.size.height = vf2.height }
        targetFrame.origin.x = min(max(vf2.minX, targetFrame.origin.x), vf2.maxX - targetFrame.width)
        targetFrame.origin.y = max(vf2.minY, currentTop - targetFrame.height)
    }
    if window.isZoomed {
        // window.zoom(nil)
        // 在 zoomed 状态下，用 delegate 指定“标准帧”= targetFrame，然后执行一次无动画 zoom
        let helper = WindowZoomHelper.shared
        let oldDelegate = window.delegate
        window.delegate = helper
        helper.pendingStandardFrame = targetFrame

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0  // 无动画切换，避免“半屏回弹”的视觉跳变
            window.zoom(nil)  // 退出 zoomed，直接采用我们提供的标准帧
        }

        helper.pendingStandardFrame = nil
        window.delegate = oldDelegate
    }                   // 退出“标准缩放”状态
    else {
        window.setFrame(targetFrame, display: true, animate: false)
    }
}


@inline(__always)
private func clamp<T: Comparable>(_ x: T, _ r: ClosedRange<T>) -> T { min(max(x, r.lowerBound), r.upperBound) }

struct Placeholder: View {
    let title: String
    let systemName: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemName).font(.system(size: 48))
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class WindowZoomHelper: NSObject, NSWindowDelegate {
    static let shared = WindowZoomHelper()
    var pendingStandardFrame: NSRect?

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
        if let f = pendingStandardFrame { return f }
        return defaultFrame
    }
}
// MARK: - Extensions

extension UTType {
    static var webPCompat: UTType {
        if let t = UTType("public.webp") { return t }
        return UTType(importedAs: "public.webp")
    }
}

extension Notification.Name {
    static let infraNext = Notification.Name("InfraView.Next")
    static let infraPrev = Notification.Name("InfraView.Prev")
}


// 小工具：把 NSItemProvider 的 loadItem 包成 async
func loadItemURL(provider: NSItemProvider, type: UTType) async -> URL? {
    await withCheckedContinuation { cont in
        provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
            if let url = item as? URL {
                cont.resume(returning: url)
            } else if let nsurl = item as? NSURL, let u = nsurl as URL? {
                cont.resume(returning: u)
            } else if let data = item as? Data {
                var stale = false
                if let u = try? URL(resolvingBookmarkData: data,
                                    options: [.withSecurityScope, .withoutUI],
                                    relativeTo: nil,
                                    bookmarkDataIsStale: &stale),
                   !stale {
                    cont.resume(returning: u)
                } else if type.conforms(to: .image) {
                    // ✅ 为常见图片类型兜底扩展名，避免用到 "img"
                    let ext: String = {
                        if let e = type.preferredFilenameExtension { return e }
                        if type.conforms(to: .png)  { return "png" }
                        if type.conforms(to: .jpeg) { return "jpg" }
                        if type.conforms(to: .tiff) { return "tiff" }
                        if type.conforms(to: .gif)  { return "gif" }
                        if type.conforms(to: .heic) { return "heic" }
                        if let webp = UTType("public.webp"), type.conforms(to: webp) { return "webp" }
                        return "img"
                    }()
                    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    try? data.write(to: tmp)
                    cont.resume(returning: tmp)
                } else {
                    cont.resume(returning: nil)
                }
            }        }
    }
}
private func loadCGForURL(_ url: URL) -> (CGImage?, CGSize, String?) {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }

    guard FileManager.default.fileExists(atPath: url.path) else { return (nil, .zero, "File does not exist.") }
    guard FileManager.default.isReadableFile(atPath: url.path) else { return (nil, .zero, "File cannot be read.") }

    let (cgOpt, pixelSize, err) = decodeCGImageApplyingOrientation(url)
    return (cgOpt, pixelSize, err)
}
