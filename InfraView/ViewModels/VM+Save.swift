//
//  VM+Save.swift
//  InfraView
//
//  Created by 王洋 on 15/11/2025.
//
import AppKit
//import Foundation
//import ImageIO
import UniformTypeIdentifiers
extension ViewerViewModel {
    @MainActor
    func saveCurrentImage() {
        guard let img = renderedImage else { return }
        guard let window = self.window ?? keyWindowOrFirstVisible() else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
        (currentURL?.deletingPathExtension().lastPathComponent ?? "image") + ".png"
        
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            write(image: img, to: url)
        }
    }
    
}

private func write(image: NSImage, to url: URL) {
    var rect = CGRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        return
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        return
    }
    do {
        try data.write(to: url)
        print("Saved image to", url.path)
    } catch {
        print("Failed to save image:", error)
    }
}
