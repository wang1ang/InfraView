// InfraView - Enhanced version (macOS, single-file, no sidebar)
// Features: open images/folders, ←/→ browse same folder, Delete to trash,
// default 100% per image, slider + preset zoom with live percent,
// precise window auto-sizing (scrollbar-aware), image preloading, robust errors.

import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit
import ImageIO


// MARK: - ContentView (drop-in replacement)

struct ContentView: View {
    @StateObject private var store = ImageStore()
    
    @AppStorage("InfraView.fitMode") private var lastFitMode: FitMode = .fitWindowToImage
    @State private var fitMode: FitMode = .fitWindowToImage
    @State private var fitModeInitialized = false
    
    @ObservedObject var viewerVM: ViewerViewModel
    @EnvironmentObject private var bar: StatusBarStore

    @State private var showImporter = false
    @State private var showDeleteConfirm = false
    @State private var toolbarWasVisible = true
    @State private var statusBarWasVisible = true
    private let zoomPresets: [CGFloat] = [0.25, 0.33, 0.5, 0.66, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 5.0]

    private var currentURL: URL? {
        guard let i = store.selection, store.imageURLs.indices.contains(i) else { return nil }
        return store.imageURLs[i]
    }

    var body: some View {
        GeometryReader { geo in
            Viewer(store: store,
                   viewerVM: viewerVM,
                   fitMode: fitMode
            )
        }
        .onDeleteCommand {
            requestDelete()
        }
        .toolbar { compactToolbar }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image, .webPCompat, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { store.load(urls: urls) }
        }
        .onAppear() {
            if !fitModeInitialized {
                fitMode = lastFitMode
                fitModeInitialized = true
            }
        }
        .onChange(of: fitMode) { _, newValue in
            lastFitMode = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraNext)) { _ in next() }
        .onReceive(NotificationCenter.default.publisher(for: .infraPrev)) { _ in previous() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            guard let win = viewerVM.window, win.isKeyWindow else { return }
            toolbarWasVisible = win.toolbar?.isVisible ?? true
            win.toolbar?.isVisible = false
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            if #available(macOS 11.0, *) { win.titlebarSeparatorStyle = .none }
            
            statusBarWasVisible = StatusBarStore.shared.isVisible
            StatusBarStore.shared.isVisible = false
            
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            guard let w = viewerVM.window, w.isKeyWindow else { return }
            w.toolbar?.isVisible = toolbarWasVisible
            w.titleVisibility = .visible
            w.titlebarAppearsTransparent = false
            if #available(macOS 11.0, *) { w.titlebarSeparatorStyle = .automatic }
            StatusBarStore.shared.isVisible = statusBarWasVisible
        }
        .onDrop(of: [UTType.fileURL, .image], isTargeted: nil) { providers in
            let canHandle = providers.contains {
                $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
                $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            }
            guard canHandle else { return false }
            Task.detached(priority: .userInitiated) {
                var urls: [URL] = []
                for p in providers {
                    if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                       let url = await loadItemURL(provider: p, type: .fileURL) { urls.append(url); continue }
                    if p.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                       let url = await loadItemURL(provider: p, type: .image) { urls.append(url) }
                }
                guard !urls.isEmpty else { return }
                await MainActor.run {
                    NSApp.activate(ignoringOtherApps: true)
                    if let win = currentWindow() {
                        win.makeKeyAndOrderFront(nil)
                    }
                    store.load(urls: urls)
                }
            }
            return true
        }
        .alert("Move to Trash", isPresented: $showDeleteConfirm, presenting: currentURL) { url in
            Button("Move to Trash", role: .destructive) {
                performDelete()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
        } message: { url in
            Text(url.lastPathComponent)
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraDelete)) { _ in
            guard viewerVM.window?.isKeyWindow == true else { return }
            let erased = viewerVM.eraseSelection()
            if !erased {
                requestDelete()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraRotate)) { note in
            let q = (note.object as? Int) ?? 0
            guard currentURL != nil else { return }
            guard let win = viewerVM.window, win.isKeyWindow else { return }
            viewerVM.rotateCurrentImage(fitMode: fitMode, by: q, window: win)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileBySystem)) { note in
            if let urls = note.object as? [URL] {
                store.load(urls: urls)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraCopy)) { note in
            guard viewerVM.window?.isKeyWindow == true else { return }
            print("InfraView Copy fired")
            
            let copiedSelection = viewerVM.copySelectionToPasteboard()
            if !copiedSelection {
                // copy file
                guard let idx = store.selection, idx < store.imageURLs.count else { return }
                let url = store.imageURLs[idx]
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([url as NSURL])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraCut)) { _ in
            if viewerVM.copySelectionToPasteboard() {
                viewerVM.eraseSelection()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraUndo)) { _ in
            guard viewerVM.window?.isKeyWindow == true else { return }
            viewerVM.undo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraRedo)) { _ in
            guard viewerVM.window?.isKeyWindow == true else { return }
            viewerVM.redo()
        }
    }

    // 工具栏绑定改到 viewerVM
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
            } label: {
                Image(systemName: viewerVM.imageAutoFit ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
            }

            Menu(content: {
                Slider(value: zoomBinding(), in: 0.25...10)
                Divider(); zoomMenuContent
            }, label: { Text("\(String(bar.zoomPercent ?? 100))%") })
                //Int(round(viewerVM.zoom*100))

            Button { previous() } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button { next() } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button { requestDelete() } label: { Image(systemName: "trash") }
                .keyboardShortcut(.delete, modifiers: [])
        }
    }
    
    @ViewBuilder
    var zoomMenuContent: some View {
        ForEach(zoomPresets, id: \.self) { z in
            Button("\(Int(z * 100))%") {
                zoomBinding().wrappedValue = z
            }
        }
    }
    
    // 将本地 UI 操作转给 VM（需要 window 参与百分比计算）
    private func zoomBinding() -> Binding<CGFloat> {
        Binding(get: { viewerVM.zoom }, set: { newV in
                viewerVM.drive(reason: .zoom(newV), mode: fitMode)
        })
    }
    
    private func next() { guard let sel = store.selection, !store.imageURLs.isEmpty else { return }; store.selection = (sel + 1) % store.imageURLs.count }
    private func previous() { guard let sel = store.selection, !store.imageURLs.isEmpty else { return }; store.selection = (sel - 1 + store.imageURLs.count) % store.imageURLs.count }
    
    private func requestDelete() {
        guard currentURL != nil else { return }
        showDeleteConfirm = true
    }
    private func performDelete() {
        guard let idx = store.selection, !store.imageURLs.isEmpty else { return }
        do {
            try store.delete(at: idx)
            store.selection = store.imageURLs.isEmpty ? nil : min(idx, store.imageURLs.count - 1)
        } catch { print("Delete failed:", error) }
    }
    
    private func currentWindow() -> NSWindow? {
        viewerVM.window ?? keyWindowOrFirstVisible()
    }
}

// MARK: - Viewer (thin wrapper)

@MainActor
struct Viewer: View {
    @ObservedObject var store: ImageStore
    @ObservedObject var viewerVM: ViewerViewModel
    @EnvironmentObject private var bar: StatusBarStore
    @ObservedObject private var sharedBar = StatusBarStore.shared
    let fitMode: FitMode

    var body: some View {
        Group {
            if let index = store.selection, index < store.imageURLs.count {
                let url = store.imageURLs[index]
                
                ZStack {
                    //Color(NSColor.windowBackgroundColor).ignoresSafeArea()

                    if let err = viewerVM.loadingError {
                        Placeholder(title: "Failed to load", systemName: "exclamationmark.triangle", text: err)
                    } else if let img = viewerVM.processedImage {
                        ZoomableImage(
                            image: img,
                            zoom: Binding(
                                get: { viewerVM.zoom },
                                set: { v in
                                        viewerVM.drive(reason: .zoom(v), mode: fitMode)
                                }
                            ),
                            fitMode: fitMode,
                            viewerVM: viewerVM,
                            onScaleChanged: { newZoom in
                                print("prev vm.zoom: ", viewerVM.zoom)
                                viewerVM.zoom = newZoom
                                bar.setZoom(percent: Int(round(newZoom * 100)))
                            },
                            onLayoutChange: nil,
                            onViewPortChange: {
                                // TODO: check this logic
                                viewerVM.fitImageToWindow()
                                bar.setZoom(percent: Int(round(viewerVM.zoom * 100)))
                            }
                        )
                        .id(url)
                        .navigationTitle(url.lastPathComponent)
                        .onAppear() {
                            bar.updateStatus(url: url, image: img, index: index, total: store.imageURLs.count)
                            bar.setZoom(percent: Int(round(viewerVM.zoom * 100)))
                        }
                    } else {
                        VStack(spacing: 12) {
                            ProgressView().progressViewStyle(CircularProgressViewStyle()).scaleEffect(1.2)
                            Text("Loading...").font(.headline).foregroundColor(.secondary)
                        }
                    }
                }
                .onChange(of: viewerVM.processedImage) { _, newImg in
                    if let newImg {
                        bar.updateStatus(url: url, image: newImg, index: index, total: store.imageURLs.count)
                        bar.setZoom(percent: Int(round(viewerVM.zoom * 100)))
                    }
                }
                .onAppear(perform: showCurrent)
                .onChange(of: store.selection) { _, _ in showCurrent() }
                .onChange(of: store.imageURLs) { _, newList in
                    // 修剪缓存（已在 ContentView 构造的 cache 上完成，若需要可在 VM 内暴露 trim）
                    // 这里无需额外处理
                }
                .onChange(of: fitMode) { _, _ in
                    guard let idx = store.selection,
                          idx < store.imageURLs.count
                    else { return }
                    viewerVM.drive(reason: .fitToggle, mode: fitMode)
                    //showCurrent()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                    showCurrent()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                    showCurrent()
                }

            } else {
                Placeholder(title: "No Selection", systemName: "rectangle.dashed", text: "Open an image (⌘O)")
            }
        }
        .onChange(of: sharedBar.isVisible) { _, _ in
            viewerVM.drive(reason: .layout, mode: fitMode)
        }
        .onChange(of: viewerVM.zoom) { _, newZoom in
            bar.setZoom(percent: Int(round(newZoom * 100)))
        }
    }

    private func showCurrent() {
        guard let idx = store.selection,
              idx < store.imageURLs.count
        else { return }
        viewerVM.show(index: idx, in: store.imageURLs, fitMode: fitMode)
    }
    private func currentWindow() -> NSWindow? {
        viewerVM.window ?? keyWindowOrFirstVisible()
    }
}

// MARK: - ZoomableImage
@inline(__always)
private func isAnimated(_ img: NSImage) -> Bool {
    img.representations.contains { ($0 as? NSBitmapImageRep)?.value(forProperty: .frameCount) as? Int ?? 0 > 1 }
}

struct ZoomedContent: View {
    let width: CGFloat
    let height: CGFloat
    let image: NSImage
    @ViewBuilder
    private func imageView(_ w: CGFloat, _ h: CGFloat) -> some View {
        if isAnimated(image) {
            AnimatedImageView(image: image)
                .frame(width: w, height: h)
        } else {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: w, height: h)
            //.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    var body: some View {
        ZStack {
            CheckerboardBackground()
                .frame(width: width, height: height)
                .clipped()
            imageView(width, height)
        }
        .frame(width: width, height: height)
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
    // File
    static let infraSave = Notification.Name("infraSave")
    
    static let infraNext = Notification.Name("InfraView.Next")
    static let infraPrev = Notification.Name("InfraView.Prev")
    static let infraDelete = Notification.Name("InfraView.Delete")
    static let infraRotate = Notification.Name("InfraView.Rotate")
    static let openFileBySystem = Notification.Name("InfraView.OpenFileBySystem")
    static let infraCopy = Notification.Name("InfraView.Copy")
    static let infraCut = Notification.Name("InfraView.Cut")
    static let infraCrop = Notification.Name("InfraView.Crop")
    static let infraSelectAll = Notification.Name("InfraView.SelectAll")
    static let infraUndo = Notification.Name("InfraView.Undo")
    static let infraRedo = Notification.Name("InfraView.Redo")
    static let infraToggleStatusBar = Notification.Name("InfraView.ToggleStatusBar")
}

// MARK: - Window Helper
@inline(__always)
func keyWindowOrFirstVisible() -> NSWindow? {
    NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
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
            }
        }
    }
}
