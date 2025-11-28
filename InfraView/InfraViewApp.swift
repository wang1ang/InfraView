//
//  InfraViewApp.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import SwiftUI

@main
struct InfraViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bar = StatusBarStore.shared
    
    var body: some Scene {
        WindowGroup {
            ContentViewWithStatusBar()
        }
        //.windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .infraSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NotificationCenter.default.post(name: .infraUndo, object: nil)
                }
                .keyboardShortcut("z", modifiers: .command)
                Button("Redo") {
                    NotificationCenter.default.post(name: .infraRedo, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Rotate Left") {
                    NotificationCenter.default.post(name: .infraRotate, object: -1)
                }.keyboardShortcut("L", modifiers: [])

                Button("Rotate Right") {
                    NotificationCenter.default.post(name: .infraRotate, object: 1)
                }.keyboardShortcut("R", modifiers: [])
                Button("Toggle Star") {
                    NotificationCenter.default.post(name: .infraToggleStar, object: nil)
                }.keyboardShortcut("S", modifiers: [])
                Toggle("Show Status Bar", isOn: $bar.isVisible)
                .keyboardShortcut("S", modifiers: [.control])
                Button("Full Screen") {
                    if let win = keyWindowOrFirstVisible() {
                        win.toggleFullScreen(nil)
                    }
                }.keyboardShortcut(KeyEquivalent("f"), modifiers: [])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NotificationCenter.default.post(name: .infraCut, object: nil)
                }.keyboardShortcut(KeyEquivalent("x"), modifiers: .command)
                Button("Copy") {
                    NotificationCenter.default.post(name: .infraCopy, object: nil)
                }.keyboardShortcut("c", modifiers: .command)
                // paste
                Button("Delete") {
                    NotificationCenter.default.post(name: .infraDelete, object: nil)
                }.keyboardShortcut(.delete, modifiers: .command)
                Button("Select All") {
                    NotificationCenter.default.post(name: .infraSelectAll, object: nil)
                }.keyboardShortcut("a", modifiers: .command)
                Button("Crop") {
                    NotificationCenter.default.post(name: .infraCrop, object: nil)
                }.keyboardShortcut("C", modifiers: [])
            }
            CommandMenu("Image") {
                Button("Vertical Flip") {
                    NotificationCenter.default.post(name: .infraFlip, object: "V")
                }.keyboardShortcut("V", modifiers: [])
                Button("Horizontal Flip") {
                    NotificationCenter.default.post(name: .infraFlip, object: "H")
                }.keyboardShortcut("H", modifiers: [])
                Divider()
                Button("Change Canvas Size") {
                    CanvasSizePanelManager.shared.show { config in
                        NotificationCenter.default.post(name: .infraCanvasSize, object: config)
                    }
                }.keyboardShortcut("V", modifiers: [.shift])
                Button("Add Border") {
                    MarginPanelManager.shared.show { config in
                        NotificationCenter.default.post(name: .infraBorder, object: config)
                    }
                }.keyboardShortcut("B", modifiers: [.shift])
            }
        }
    }
}

struct ContentViewWithStatusBar: View {
    @StateObject private var viewerVM: ViewerViewModel
    @ObservedObject private var sharedBar = StatusBarStore.shared

    init() {
        let repo = ImageRepositoryImpl()
        let cache = ImageCache(capacity: 8)
        let preloader = ImagePreloader(repo: repo, cache: cache)
        let sizer = WindowSizerImpl()

        let vm = ViewerViewModel(repo: repo, cache: cache, preloader: preloader, sizer: sizer)

        _viewerVM = StateObject(wrappedValue: vm)
    }

    var body: some View {
        VStack(spacing: 0) {
            ContentView(viewerVM: viewerVM)
                .environmentObject(viewerVM.bar) // need observe
            if sharedBar.isVisible {
                StatusBar()
                    .environmentObject(viewerVM.bar)
                    .frame(height: sharedBar.height)
            }
        }
    }
}

// Used only for exit window by clicking the X
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true  // ✅ 当最后一个窗口被关闭时退出程序
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .openFileBySystem, object: urls)
    }
}
