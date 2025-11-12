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
                .environmentObject(bar)
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
    @ObservedObject private var bar = StatusBarStore()

    var body: some View {
        VStack(spacing: 0) {
            ContentView()
                .environmentObject(bar)
            if bar.isVisible {
                StatusBar()
                    .environmentObject(bar)
                    .frame(height: bar.height)
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
