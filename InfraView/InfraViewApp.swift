//
//  InfraViewApp.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import SwiftUI

@main
struct InfraViewApp: App {
    init() {
        bindDeleteToCommandBackspace()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        //.windowStyle(.titleBar)
    }
}
