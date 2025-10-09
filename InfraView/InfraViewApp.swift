//
//  InfraViewApp.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import SwiftUI

@main
struct InfraViewApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandMenu("Edit") {
                Button("Move to Trash") {
                    NotificationCenter.default.post(name: .infraDelete, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])
                Button("Move to Trash") {
                    NotificationCenter.default.post(name: .infraDelete, object: nil)
                }
                .keyboardShortcut(.deleteForward, modifiers: [])
                Button("Move to Trash") {
                    NotificationCenter.default.post(name: .infraDelete, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
    }
}
