//
//  Extensions.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - UTType Extensions

extension UTType {
    static var webPCompat: UTType {
        if let t = UTType("public.webp") { return t }
        return UTType(importedAs: "public.webp")
    }
}

// MARK: - NSImage Extensions

extension NSImage {
    var cgImageSafe: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

// MARK: - NSEvent Extensions

extension NSEvent {
    var hasCommand: Bool {
        modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
    }
}

// MARK: - Window Helpers

/// 获取当前关键窗口或第一个可见窗口
@MainActor
func keyWindowOrFirstVisible() -> NSWindow? {
    NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
}

