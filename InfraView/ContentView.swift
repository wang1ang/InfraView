// InfraView - Stable version (macOS, single-file, no sidebar)
// Features: open images/folders, ←/→ browse same folder, Delete to trash,
// default 100% per image, slider + preset zoom with live percent,
// precise window auto-sizing with scrollbar-aware, screen-based one-pass prediction.

import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

// MARK: - Model
final class ImageStore: ObservableObject {
    @Published var imageURLs: [URL] = []
    @Published var selection: Int? = nil

    func load(urls: [URL]) {
        var collected: [URL] = []
        let fm = FileManager.default
        let exts: Set<String> = ["png","jpg","jpeg","gif","tiff","bmp","heic","webp"]

        if urls.count == 1, let first = urls.first {
            let access = first.startAccessingSecurityScopedResource()
            defer { if access { first.stopAccessingSecurityScopedResource() } }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: first.path, isDirectory: &isDir), !isDir.boolValue {
                let dir = first.deletingLastPathComponent()
                let dirAccess = dir.startAccessingSecurityScopedResource()
                defer { if dirAccess { dir.stopAccessingSecurityScopedResource() } }
                if let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let f as URL in e {
                        if exts.contains(f.pathExtension.lowercased()) { collected.append(f) }
                    }
                }
                if collected.isEmpty { imageURLs = [first]; selection = 0 } else {
                    collected.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    imageURLs = collected
                    selection = imageURLs.firstIndex(of: first) ?? 0
                }
                return
            }
        }
        func collect(from url: URL) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let f as URL in e {
                        if exts.contains(f.pathExtension.lowercased()) { collected.append(f) }
                    }
                }
            } else if exts.contains(url.pathExtension.lowercased()) {
                collected.append(url)
            }
        }
        urls.forEach { collect(from: $0) }
        imageURLs = collected.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        selection = imageURLs.isEmpty ? nil : 0
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
    @State private var fitToScreen: Bool = false // default 100%
    @State private var showImporter = false
    @State private var scalePercent: Int = 100
    private let zoomPresets: [CGFloat] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0]

    var body: some View {
        Viewer(store: store, zoom: $zoom, fitToScreen: $fitToScreen) { p in
            scalePercent = p
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button { showImporter = true } label: { Label("Open", systemImage: "folder") }
                Toggle(isOn: $fitToScreen) { Label("Fit", systemImage: fitToScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }
                    .toggleStyle(.button)
                HStack { Image(systemName: "minus.magnifyingglass"); Slider(value: $zoom, in: 0.25...4); Image(systemName: "plus.magnifyingglass") }
                Menu(content: {
                    Button("Fit") { fitToScreen = true }
                    Divider()
                    ForEach(zoomPresets, id: \.self) { z in
                        Button("\(Int(z * 100))%") { fitToScreen = false; zoom = z }
                    }
                }, label: { Text("\(scalePercent)%") })
                Button { previous() } label: { Label("Prev", systemImage: "chevron.left") }.keyboardShortcut(.leftArrow, modifiers: [])
                Button { next() } label: { Label("Next", systemImage: "chevron.right") }.keyboardShortcut(.rightArrow, modifiers: [])
                Button { deleteCurrent() } label: { Label("Delete", systemImage: "trash") }.keyboardShortcut(.delete, modifiers: [])
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image, .png, .jpeg, .tiff, .gif, .bmp, .heic, .webP, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                store.load(urls: urls)
                if store.selection == nil, !store.imageURLs.isEmpty { store.selection = 0 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraNext)) { _ in next() }
        .onReceive(NotificationCenter.default.publisher(for: .infraPrev)) { _ in previous() }
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

    var body: some View {
        if let index = store.selection, index < store.imageURLs.count {
            let url = store.imageURLs[index]
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()
                if let img = loadImage(url: url) {
                    ZoomableImage(image: img, zoom: $zoom, fitToScreen: $fitToScreen, onScaleChanged: onScaleChanged)
                        .id(url)
                        .onAppear { resetForNewImage(img) }
                        .onChange(of: store.selection) { _, _ in resetForNewImage(img) }
                        .onChange(of: fitToScreen) { _, newValue in
                            let size = newValue ? fittedContentSize(for: img) : scaledContentSize(for: img, scale: zoom)
                            resizeWindowToContentSize(size)
                        }
                        .onChange(of: zoom) { _, newZoom in
                            if !fitToScreen { resizeWindowToContentSize(scaledContentSize(for: img, scale: newZoom)) }
                        }
                        .navigationTitle(url.lastPathComponent)
                } else {
                    Placeholder(title: "Failed to load", systemName: "exclamationmark.triangle", text: url.lastPathComponent)
                }
            }
        } else {
            Placeholder(title: "No Selection", systemName: "rectangle.dashed", text: "Open an image (⌘O)")
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
private func loadImage(url: URL) -> NSImage? {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    if let img = NSImage(contentsOf: url) { return img }
    if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) { return NSImage(data: data) }
    return nil
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

/// Scrollbar thickness for legacy (non-overlay) style; overlay bars take no space.
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

// Screen-based one-pass prediction: only if desired content exceeds visibleFrame, pre-reserve scrollbar thickness once
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

    // Pre-reserve only when the desired content would overflow the screen-visible area
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
