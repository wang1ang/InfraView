// InfraView - Enhanced version (macOS, single-file, no sidebar)
// Features: open images/folders, ←/→ browse same folder, Delete to trash,
// default 100% per image, slider + preset zoom with live percent,
// precise window auto-sizing (scrollbar-aware), image preloading, robust errors.

import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

// MARK: - Model

enum FitMode: String, CaseIterable {
    case fitWindowToImage = "Fit window to image"
    case fitImageToWindow = "Fit image to window"
    case fitOnlyBigToWindow = "Fit only big images to window"
    case fitOnlyBigToDesktop = "Fit only big images to desktop"
    case doNotFit = "Do not fit anything"
}

final class ImageStore: ObservableObject {
    @Published var imageURLs: [URL] = []
    @Published var selection: Int? = nil

    func load(urls: [URL]) {
        let fm = FileManager.default
        let exts: Set<String> = ["png","jpg","jpeg","gif","tiff","bmp","heic","webp"]
        var collected: [URL] = []
        var urlsToProcess = urls
        var initialSelectionURL: URL? = nil

        if urls.count == 1, let first = urls.first {
            let access = first.startAccessingSecurityScopedResource()
            defer { if access { first.stopAccessingSecurityScopedResource() } }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: first.path, isDirectory: &isDir), !isDir.boolValue {
                urlsToProcess = [first.deletingLastPathComponent()]
                initialSelectionURL = first
            }
        }

        for url in urlsToProcess {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                do {
                    let files = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                    for fileURL in files {
                        let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                        if vals?.isRegularFile == true && exts.contains(fileURL.pathExtension.lowercased()) {
                            collected.append(fileURL)
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
    private let zoomPresets: [CGFloat] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0]
    @State private var windowWidth: CGFloat = 800

    var body: some View {
        GeometryReader { geometry in
            Viewer(store: store, zoom: $zoom, fitToScreen: $fitToScreen, fitMode: fitMode) { p in
                scalePercent = p
            }
            .onAppear { windowWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { _, newW in windowWidth = newW }
        }
        .toolbar {
            if windowWidth > 750 {
                fullToolbar
            } else {
                compactToolbar
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image, .png, .jpeg, .tiff, .gif, .bmp, .heic, .webPCompat, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { store.load(urls: urls) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraNext)) { _ in next() }
        .onReceive(NotificationCenter.default.publisher(for: .infraPrev)) { _ in previous() }
    }

    var fullToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button { showImporter = true } label: { Label("Open", systemImage: "folder") }
                .keyboardShortcut("o", modifiers: [.command])

            Menu {
                ForEach(FitMode.allCases, id: \.self) { mode in
                    Button(action: { fitMode = mode }) {
                        HStack { Text(mode.rawValue); Spacer(); if fitMode == mode { Image(systemName: "checkmark") } }
                    }
                }
                Divider()
                Toggle(isOn: $fitToScreen) { Text("Manual Fit Toggle") }
            } label: {
                Label("Fit", systemImage: fitToScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
            }

            HStack {
                Image(systemName: "minus.magnifyingglass")
                Slider(value: Binding(get: { zoom }, set: { v in fitToScreen = false; zoom = v }), in: 0.25...4)
                Image(systemName: "plus.magnifyingglass")
            }
            .frame(minWidth: 150)
            Menu(content: { zoomMenuContent }, label: { Text("\(scalePercent)%") })

            Button { previous() } label: { Label("Prev", systemImage: "chevron.left") }.keyboardShortcut(.leftArrow, modifiers: [])
            Button { next() } label: { Label("Next", systemImage: "chevron.right") }.keyboardShortcut(.rightArrow, modifiers: [])
            Button { deleteCurrent() } label: { Label("Delete", systemImage: "trash") }.keyboardShortcut(.delete, modifiers: [])
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
                Divider()
                Toggle(isOn: $fitToScreen) { Text("Manual Fit Toggle") }
            } label: { Image(systemName: fitToScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }

            Menu(content: {
                Slider(value: Binding(get: { zoom }, set: { v in fitToScreen = false; zoom = v }), in: 0.25...4)
                Divider(); zoomMenuContent
            }, label: { Text("\(scalePercent)%") })

            Button { previous() } label: { Image(systemName: "chevron.left") }.keyboardShortcut(.leftArrow, modifiers: [])
            Button { next() } label: { Image(systemName: "chevron.right") }.keyboardShortcut(.rightArrow, modifiers: [])
            Button { deleteCurrent() } label: { Image(systemName: "trash") }.keyboardShortcut(.delete, modifiers: [])
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
                                resizeWindowToContentSize(contentSize)
                            case .fitOnlyBigToWindow, .doNotFit:
                                break
                            }
                        }
                    )
                    .id(url)
                    .onChange(of: fitToScreen) { _, newValue in
                        let size = newValue ? fittedContentSize(for: img) : scaledContentSize(for: img, scale: zoom)
                        if fitMode == .fitWindowToImage && !newValue { resizeWindowToContentSize(size) }
                        else if fitMode == .fitOnlyBigToDesktop && newValue { resizeWindowToContentSize(size) }
                    }
                    .onChange(of: zoom) { _, newZoom in
                        if !fitToScreen && fitMode == .fitWindowToImage {
                            resizeWindowToContentSize(scaledContentSize(for: img, scale: newZoom))
                        }
                    }
                    .navigationTitle(url.lastPathComponent)
                } else {
                    Placeholder(title: "No image", systemName: "photo", text: url.lastPathComponent)
                }
            }
            .onAppear(perform: loadImageForSelection)
            .onChange(of: store.selection) { _, _ in loadImageForSelection(); preloadAdjacentImages() }
            .onChange(of: fitMode) { _, _ in if let img = currentImage { resetForNewImage(img) } }
        } else {
            Placeholder(title: "No Selection", systemName: "rectangle.dashed", text: "Open an image (⌘O)")
        }
    }

    private func loadImageForSelection() {
        guard let index = store.selection, index < store.imageURLs.count else { currentImage = nil; loadingError = nil; return }
        let url = store.imageURLs[index]

        if let cached = preloadedImages[url] {
            currentImage = cached; loadingError = nil; isLoading = false; resetForNewImage(cached); return
        }
        isLoading = true; loadingError = nil; currentImage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let (image, error) = loadImageWithError(url: url)
            DispatchQueue.main.async {
                self.isLoading = false; self.currentImage = image; self.loadingError = error
                if let img = image { resetForNewImage(img); preloadedImages[url] = img }
            }
        }
    }

    private func preloadAdjacentImages() {
        guard let current = store.selection, !store.imageURLs.isEmpty else { return }
        let urls = store.imageURLs
        let indices = [(current - 1 + urls.count) % urls.count, (current + 1) % urls.count]
        for i in indices {
            let u = urls[i]
            if preloadedImages[u] != nil { continue }
            DispatchQueue.global(qos: .background).async {
                let (image, _) = loadImageWithError(url: u)
                if let image {
                    DispatchQueue.main.async {
                        if preloadedImages.count > 5 {
                            if let first = preloadedImages.keys.first { preloadedImages.removeValue(forKey: first) }
                            if let first = preloadedImages.keys.first { preloadedImages.removeValue(forKey: first) }
                        }
                        preloadedImages[u] = image
                    }
                }
            }
        }
    }

    private func resetForNewImage(_ img: NSImage) {
        let naturalSize = naturalPointSize(img)
        switch fitMode {
        case .fitWindowToImage:
            fitToScreen = false; zoom = 1; resizeWindowToContentSize(naturalSize)
        case .fitImageToWindow:
            fitToScreen = true; zoom = 1
        case .fitOnlyBigToWindow:
            let vf = (NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
            let padding: CGFloat = 100
            let maxW = max(vf.width - padding, 200)
            let maxH = max(vf.height - padding, 200)
            if naturalSize.width > maxW || naturalSize.height > maxH { fitToScreen = true; zoom = 1 }
            else { fitToScreen = false; zoom = 1; resizeWindowToContentSize(naturalSize) }
        case .fitOnlyBigToDesktop:
            let screenFrame = NSScreen.main?.frame ?? .zero
            let padding: CGFloat = 50
            let maxW = max(screenFrame.width - padding, 200)
            let maxH = max(screenFrame.height - padding, 200)
            if naturalSize.width > maxW || naturalSize.height > maxH {
                fitToScreen = true; zoom = 1
                let fitted = fittedContentSize(for: img)
                resizeWindowToContentSize(fitted)
            } else {
                fitToScreen = false; zoom = 1; resizeWindowToContentSize(naturalSize)
            }
        case .doNotFit:
            fitToScreen = false; zoom = 1
        }

        // 更新百分比
        let vf = (NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
        let padding: CGFloat = 32
        let maxW = max(vf.width - padding, 200)
        let maxH = max(vf.height - padding, 200)
        let scale = computeScale(isFit: fitToScreen, baseW: naturalSize.width, baseH: naturalSize.height, maxW: maxW, maxH: maxH, zoom: zoom)
        onScaleChanged(Int(round(scale * 100)))
    }
}

// MARK: - ZoomableImage

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
            let needScroll = (contentW > maxW) || (contentH > maxH)

            let view = Group {
                if needScroll {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: contentW, height: contentH)
                    }
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: contentW, height: contentH)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear { baseZoom = zoom; onScaleChanged(Int(round(currentScale * 100))) }
            .onChange(of: fitToScreen) { _, newFit in
                let cs = computeScale(isFit: newFit, baseW: baseW, baseH: baseH, maxW: maxW, maxH: maxH, zoom: zoom)
                onScaleChanged(Int(round(cs * 100)))
            }
            .onChange(of: zoom) { _, newZoom in if !fitToScreen { onScaleChanged(Int(round(newZoom * 100))) } }
            .onChange(of: needScroll) { _, newNeed in onLayoutChange?(newNeed, CGSize(width: contentW, height: contentH)) }

            view
                .gesture(
                    MagnificationGesture()
                        .onChanged { v in fitToScreen = false; zoom = clamp(baseZoom * v, 0.25...4) }
                        .onEnded { _ in baseZoom = zoom }
                )
        }
    }
}

// MARK: - Helpers

private func computeScale(isFit: Bool, baseW: CGFloat, baseH: CGFloat, maxW: CGFloat, maxH: CGFloat, zoom: CGFloat) -> CGFloat {
    let fitScale = min(maxW / baseW, maxH / baseH)
    return isFit ? fitScale : zoom
}

private func loadImageWithError(url: URL) -> (NSImage?, String?) {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    guard FileManager.default.fileExists(atPath: url.path) else { return (nil, "文件不存在") }
    guard FileManager.default.isReadableFile(atPath: url.path) else { return (nil, "文件无法读取") }
    if let img = NSImage(contentsOf: url) { return (img, nil) }
    do { let data = try Data(contentsOf: url, options: [.mappedIfSafe]); if let img = NSImage(data: data) { return (img, nil) } else { return (nil, "不支持的图片格式") } }
    catch { return (nil, "读取文件失败: \(error.localizedDescription)") }
}

private func displayScaleFactor() -> CGFloat {
    if let w = NSApp.keyWindow, let s = w.screen { return s.backingScaleFactor }
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

private func fittedContentSize(for image: NSImage) -> CGSize {
    let base = naturalPointSize(image)
    let vf = (NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
    let padding: CGFloat = 32
    let maxW = max(vf.width - padding, 200)
    let maxH = max(vf.height - padding, 200)
    let scale = min(maxW / max(base.width, 1), maxH / max(base.height, 1))
    return CGSize(width: ceil(min(base.width * scale, maxW)), height: ceil(min(base.height * scale, maxH)))
}

private func scaledContentSize(for image: NSImage, scale: CGFloat) -> CGSize {
    let base = naturalPointSize(image)
    let vf = (NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
    let padding: CGFloat = 32
    let maxW = max(vf.width - padding, 200)
    let maxH = max(vf.height - padding, 200)
    return CGSize(width: ceil(min(base.width * scale, maxW)), height: ceil(min(base.height * scale, maxH)))
}

private func resizeWindowToContentSize(_ desiredContentSize: CGSize) {
    guard let window = NSApp.keyWindow else { return }

    let minW: CGFloat = 360, minH: CGFloat = 280
    // 想要的“SwiftUI 可布局区域”尺寸
    var layoutW = max(ceil(desiredContentSize.width), minW)
    var layoutH = max(ceil(desiredContentSize.height), minH)

    // 当前窗口下：contentRect 与 contentLayoutRect 的差值（工具栏等占用）
    let currentFrame = window.frame
    let currentContentRect = window.contentRect(forFrameRect: currentFrame)
    let currentLayoutRect = window.contentLayoutRect
    let layoutExtraW = max(0, currentContentRect.width  - currentLayoutRect.width)
    let layoutExtraH = max(0, currentContentRect.height - currentLayoutRect.height)

    // 目标 contentRect = 目标 layout 尺寸 + 这段“layout 被吃掉的差值”
    var contentW = layoutW + layoutExtraW
    var contentH = layoutH + layoutExtraH + 1 // +1 防 1px 缝

    // 估计滚动条（仅 legacy）占位，避免算小
    let (vBar, hBar) = legacyScrollbarThickness()
    let vf = (window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
    let padding: CGFloat = 32

    // 屏幕内最大 contentRect 尺寸（不含装饰）
    let testContentRect = NSRect(x: 0, y: 0, width: 100, height: 100)
    let testFrame = window.frameRect(forContentRect: testContentRect)
    let decoW = testFrame.width  - testContentRect.width
    let decoH = testFrame.height - testContentRect.height
    var availW = max(vf.width  - padding - decoW, minW)
    var availH = max(vf.height - padding - decoH, minH)

    // 两次迭代，收敛是否需要滚动条并给内容预留条宽
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

    // 反推窗口帧；保持窗口顶边不动
    var targetFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH))
    let currentTop = window.frame.maxY
    targetFrame.origin.x = window.frame.origin.x
    targetFrame.origin.y = currentTop - targetFrame.height

    // 屏幕边界约束
    if let screen = window.screen {
        let vf2 = screen.visibleFrame
        if targetFrame.width  > vf2.width  { targetFrame.size.width  = vf2.width }
        if targetFrame.height > vf2.height { targetFrame.size.height = vf2.height }
        targetFrame.origin.x = min(max(vf2.minX, targetFrame.origin.x), vf2.maxX - targetFrame.width)
        targetFrame.origin.y = max(vf2.minY, currentTop - targetFrame.height)
    }

    window.setFrame(targetFrame, display: true, animate: false)
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


