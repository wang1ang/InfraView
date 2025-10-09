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
    init() {
        bindDeleteToCommandBackspace()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
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
            }
        }
    }
}


// Used only for exit window by clicking the X
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true  // ✅ 当最后一个窗口被关闭时退出程序
    }
}
