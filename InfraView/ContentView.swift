// InfraView - Enhanced version (macOS, single-file, no sidebar)
// Features: open images/folders, ←/→ browse same folder, Delete to trash,
// default 100% per image, slider + preset zoom with live percent,
// precise window auto-sizing with scrollbar-aware, screen-based one-pass prediction,
// enhanced error handling and image preloading for better performance.

import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

// MARK: - Model
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
                    // 使用 contentsOfDirectory 进行浅层遍历，不再进入子文件夹
                    let files = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                    
                    for fileURL in files {
                        // 增加一个判断，确保我们只处理文件，而不是子文件夹
                        let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                        if resourceValues?.isRegularFile == true && exts.contains(fileURL.pathExtension.lowercased()) {
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
        imageURLs = uniqueURLs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        
        if let url = initialSelectionURL, let index = imageURLs.firstIndex(of: url) {
            selection = index
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
    private let zoomPresets: [CGFloat] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0]
    
    @State private var windowWidth: CGFloat = 800

    var body: some View {
        GeometryReader { geometry in
            Viewer(store: store, zoom: $zoom, fitToScreen: $fitToScreen) { p in
                scalePercent = p
            }
            .onAppear {
                windowWidth = geometry.size.width
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                windowWidth = newWidth
            }
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
            allowedContentTypes: [.image, .png, .jpeg, .tiff, .gif, .bmp, .heic, .webP, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                store.load(urls: urls)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraNext)) { _ in next() }
        .onReceive(NotificationCenter.default.publisher(for: .infraPrev)) { _ in previous() }
    }
    
    var fullToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button { showImporter = true } label: { Label("Open", systemImage: "folder") }
            Toggle(isOn: $fitToScreen) { Label("Fit", systemImage: fitToScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }
                .toggleStyle(.button)
            HStack { Image(systemName: "minus.magnifyingglass"); Slider(value: $zoom, in: 0.25...4); Image(systemName: "plus.magnifyingglass") }
                .frame(minWidth: 150)
            Menu(content: {
                zoomMenuContent
            }, label: { Text("\(scalePercent)%") })
            
            Button { previous() } label: { Label("Prev", systemImage: "chevron.left") }.keyboardShortcut(.leftArrow, modifiers: [])
            Button { next() } label: { Label("Next", systemImage: "chevron.right") }.keyboardShortcut(.rightArrow, modifiers: [])
            Button { deleteCurrent() } label: { Label("Delete", systemImage: "trash") }.keyboardShortcut(.delete, modifiers: [])
        }
    }
    
    var compactToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button { showImporter = true } label: { Image(systemName: "folder") }
            Toggle(isOn: $fitToScreen) { Image(systemName: fitToScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }
                .toggleStyle(.button)

            Menu(content: {
                Slider(value: $zoom, in: 0.25...4)
                Divider()
                zoomMenuContent
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
        ForEach(zoomPresets, id: \.self) { z in
            Button("\(Int(z * 100))%") { fitToScreen = false; zoom = z }
        }
    }

    private func next() {
        guard let sel = store.selection, !store.imageURLs.isEmpty else { return }
        store.selection = (sel + 1) % store.imageURLs.count
    }
    private func previous() {
        guard let sel = store.selection, !store.imageURLs.isEmpty else { return }
        store.selection = (sel - 1 + store.imageURLs.count) % store.imageURLs.count
    }
    private func deleteCurrent() {
        guard let idx = store.selection, !store.imageURLs.isEmpty else { return }
        do {
            try store.delete(at: idx)
            if store.imageURLs.isEmpty { store.selection = nil } else { store.selection = idx % store.imageURLs.count }
        } catch { print("Delete failed:", error) }
    }
}

// MARK: - Viewer
struct Viewer: View {
    @ObservedObject var store: ImageStore
    @Binding var zoom: CGFloat
    @Binding var fitToScreen: Bool
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
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                        Text("Loading...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                } else if let error = loadingError {
                    Placeholder(title: "Failed to load", systemName: "exclamationmark.triangle", text: error)
                } else if let img = currentImage {
                    ZoomableImage(image: img, zoom: $zoom, fitToScreen: $fitToScreen, onScaleChanged: onScaleChanged)
                        .id(url)
                        .onChange(of: fitToScreen) { _, newValue in
                            let size = newValue ? fittedContentSize(for: img) : scaledContentSize(for: img, scale: zoom)
                            resizeWindowToContentSize(size)
                        }
                        .onChange(of: zoom) { _, newZoom in
                            if !fitToScreen { resizeWindowToContentSize(scaledContentSize(for: img, scale: newZoom)) }
                        }
                        .navigationTitle(url.lastPathComponent)
                } else {
                    Placeholder(title: "No image", systemName: "photo", text: url.lastPathComponent)
                }
            }
            .onAppear(perform: loadImageForSelection)
            .onChange(of: store.selection) { _, _ in
                loadImageForSelection()
                preloadAdjacentImages()
            }
        } else {
            Placeholder(title: "No Selection", systemName: "rectangle.dashed", text: "Open an image (⌘O)")
        }
    }

    private func loadImageForSelection() {
        guard let index = store.selection, index < store.imageURLs.count else {
            currentImage = nil
            loadingError = nil
            return
        }
        
        let url = store.imageURLs[index]
        
        // 检查预加载缓存
        if let preloadedImage = preloadedImages[url] {
            currentImage = preloadedImage
            loadingError = nil
            isLoading = false
            resetForNewImage(preloadedImage)
            return
        }
        
        isLoading = true
        loadingError = nil
        currentImage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let (image, error) = loadImageWithError(url: url)
            
            DispatchQueue.main.async {
                self.isLoading = false
                self.currentImage = image
                self.loadingError = error
                
                if let img = image {
                    resetForNewImage(img)
                    // 将成功加载的图片加入预加载缓存
                    preloadedImages[url] = img
                }
            }
        }
    }
    
    private func preloadAdjacentImages() {
        guard let current = store.selection, !store.imageURLs.isEmpty else { return }
        let urls = store.imageURLs
        
        DispatchQueue.global(qos: .background).async {
            // 预加载前一张和后一张
            let indicesToPreload = [
                (current - 1 + urls.count) % urls.count,
                (current + 1) % urls.count
            ]
            
            for index in indicesToPreload {
                let url = urls[index]
                if preloadedImages[url] == nil {
                    let (image, _) = loadImageWithError(url: url)
                    if let image = image {
                        DispatchQueue.main.async {
                            // 限制缓存大小，避免内存占用过多
                            if preloadedImages.count > 5 {
                                // 移除一些较早的缓存项
                                let urlsToRemove = Array(preloadedImages.keys.prefix(2))
                                for urlToRemove in urlsToRemove {
                                    preloadedImages.removeValue(forKey: urlToRemove)
                                }
                            }
                            preloadedImages[url] = image
                        }
                    }
                }
            }
        }
    }

    private func resetForNewImage(_ img: NSImage) {
        fitToScreen = false
        zoom = 1
        onScaleChanged(100)
        resizeWindowToContentSize(naturalPointSize(img))
    }
}

// MARK: - Zoomable Image
struct ZoomableImage: View {
    let image: NSImage
    @Binding var zoom: CGFloat
    @Binding var fitToScreen: Bool
    var onScaleChanged: (Int) -> Void

    var body: some View {
        let vf = (NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
        let padding: CGFloat = 32
        let maxW = max(vf.width - padding, 200)
        let maxH = max(vf.height - padding, 200)

        let naturalPt = naturalPointSize(image)
        let baseW = max(naturalPt.width, 1)
        let baseH = max(naturalPt.height, 1)
        let fitScale = min(maxW / baseW, maxH / baseH)
        let currentScale: CGFloat = fitToScreen ? fitScale : zoom

        let contentW = baseW * currentScale
        let contentH = baseH * currentScale
        let needScroll = (contentW > maxW) || (contentH > maxH)

        Group {
            if needScroll {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: contentW, height: contentH)
                }
                .gesture(MagnificationGesture().onChanged { v in
                    fitToScreen = false
                    zoom = clamp(zoom * v, 0.25...4)
                })
            } else {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: contentW, height: contentH)
            }
        }
        .onAppear { onScaleChanged(Int(round(currentScale * 100))) }
        .onChange(of: fitToScreen) { _, _ in onScaleChanged(Int(round(currentScale * 100))) }
        .onChange(of: zoom) { _, _ in if !fitToScreen { onScaleChanged(Int(round(zoom * 100))) } }
    }
}

// MARK: - Helpers
private func loadImageWithError(url: URL) -> (NSImage?, String?) {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    
    // 首先检查文件是否存在
    guard FileManager.default.fileExists(atPath: url.path) else {
        return (nil, "文件不存在")
    }
    
    // 检查文件是否可读
    guard FileManager.default.isReadableFile(atPath: url.path) else {
        return (nil, "文件无法读取")
    }
    
    // 尝试直接从 URL 加载
    if let img = NSImage(contentsOf: url) {
        return (img, nil)
    }
    
    // 尝试从数据加载
    do {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        if let img = NSImage(data: data) {
            return (img, nil)
        } else {
            return (nil, "不支持的图片格式")
        }
    } catch {
        return (nil, "读取文件失败: \(error.localizedDescription)")
    }
}

private func displayScaleFactor() -> CGFloat {
    if let w = NSApp.keyWindow, let s = w.screen { return s.backingScaleFactor }
    return NSScreen.main?.backingScaleFactor ?? 2.0
}

private func pixelSize(_ img: NSImage) -> CGSize {
    var maxW = 0, maxH = 0
    for rep in img.representations where rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
        maxW = max(maxW, rep.pixelsWide)
        maxH = max(maxH, rep.pixelsHigh)
    }
    if maxW == 0 || maxH == 0, let tiff = img.tiffRepresentation, let b = NSBitmapImageRep(data: tiff) {
        maxW = max(maxW, b.pixelsWide)
        maxH = max(maxH, b.pixelsHigh)
    }
    if maxW == 0 || maxH == 0 {
        let sf = displayScaleFactor()
        let w = Int(img.size.width * sf), h = Int(img.size.height * sf)
        if w > 0 && h > 0 { maxW = w; maxH = h }
    }
    return CGSize(width: CGFloat(maxW), height: CGFloat(maxH))
}

private func naturalPointSize(_ img: NSImage) -> CGSize {
    let px = pixelSize(img)
    let sf = displayScaleFactor()
    return CGSize(width: px.width / sf, height: px.height / sf)
}

private func legacyScrollbarThickness() -> (vertical: CGFloat, horizontal: CGFloat) {
    if NSScroller.preferredScrollerStyle == .overlay { return (0, 0) }
    let t = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    return (vertical: t, horizontal: t)
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

    var desiredW = max(desiredContentSize.width, minW)
    var desiredH = max(desiredContentSize.height, minH)

    let vf = (window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
    let padding: CGFloat = 32
    let availW0 = max(vf.width - padding, minW)
    let availH0 = max(vf.height - padding, minH)

    let (vBar, hBar) = legacyScrollbarThickness()

    var needV = desiredH > availH0
    var needH = desiredW > availW0
    if needV || needH {
        var availW = availW0
        var availH = availH0
        for _ in 0..<2 {
            if needV { availW -= vBar }
            if needH { availH -= hBar }
            let nV = desiredH > availH
            let nH = desiredW > availW
            if nV == needV && nH == needH { break }
            needV = nV; needH = nH
        }
        if needV { desiredW += vBar }
        if needH { desiredH += hBar }
    }

    var targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: desiredW, height: desiredH)))
    let current = window.frame
    let topY = current.maxY
    targetFrame.origin.x = current.origin.x
    targetFrame.origin.y = topY - targetFrame.size.height

    if let screen = window.screen {
        let vf2 = screen.visibleFrame
        targetFrame.size.width = min(targetFrame.size.width, vf2.width)
        targetFrame.size.height = min(targetFrame.size.height, vf2.height)
        targetFrame.origin.x = min(max(vf2.minX, targetFrame.origin.x), vf2.maxX - targetFrame.size.width)
        targetFrame.origin.y = max(vf2.minY, topY - targetFrame.size.height)
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

extension UTType { static let webP = UTType(importedAs: "public.webp") }

extension Notification.Name {
    static let infraNext = Notification.Name("InfraView.Next")
    static let infraPrev = Notification.Name("InfraView.Prev")
}
