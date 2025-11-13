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

    init() {
        bindDeleteToCommandBackspace()
    }
    var body: some Scene {
        WindowGroup {
            ContentViewWithStatusBar()
        }
        //.windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Rotate Left") {
                    NotificationCenter.default.post(name: .infraRotate, object: -1)
                }
                .keyboardShortcut("L", modifiers: [])

                Button("Rotate Right") {
                    NotificationCenter.default.post(name: .infraRotate, object: 1)
                }

                .keyboardShortcut("R", modifiers: [])

                Toggle("Show Status Bar", isOn: $bar.isVisible)
                .keyboardShortcut("S", modifiers: [])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    NotificationCenter.default.post(name: .infraCopy, object: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
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
