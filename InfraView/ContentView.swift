//
//  ContentView.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

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
            // TODO: consider next image by click here
            /*
            .onTapGesture(count: 2) {
                if let win = keyWindowOrFirstVisible() {
                    win.toggleFullScreen(nil)
                }
            }*/
        }
        .onDeleteCommand {
            requestDelete()
        }
        .toolbar { compactToolbar }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image, .rawImage, .webPCompat, .folder],
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
        .onReceive(NotificationCenter.default.publisher(for: .infraNext)) { _ in
            guard let win = viewerVM.window, win.isKeyWindow else { return }
            next()
        }
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
            //guard currentURL != nil else { return }
            guard let win = viewerVM.window, win.isKeyWindow else { return }
            viewerVM.rotateCurrentImage(fitMode: fitMode, by: q)
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraFlip)) { note in
            //guard currentURL != nil else { return }
            guard let direction = note.object as? String,
                  let win = viewerVM.window,
                  win.isKeyWindow else { return }
            viewerVM.flipCurrentImage(by: direction)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.infraCanvasSize)) { note in
            guard let config = note.object as? CanvasSizeConfig,
                  let win = viewerVM.window,
                  win.isKeyWindow else { return }
            viewerVM.changeCanvasSize(config)
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
                Slider(value: zoomBinding(), in: 0.05...20)
                Divider(); zoomMenuContent
            }, label: { Text("\(String(bar.zoomPercent ?? 100))%") })

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
    private var isFullScreen: Bool {
        currentWindow()?.styleMask.contains(.fullScreen) == true
    }
}

