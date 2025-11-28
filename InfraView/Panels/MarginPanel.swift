//
//  MarginPanel.swift
//  InfraView
//
//  Created by 王洋 on 2025.
//

import SwiftUI

struct MarginConfig: Equatable {
    var top: String = "", bottom: String = "", left: String = "", right: String = ""
    var putBorderInside = false
    var isComplete: Bool { !top.isEmpty && !bottom.isEmpty && !left.isEmpty && !right.isEmpty }
}

struct MarginPanelView: View {
    @State private var config = MarginConfig()
    @State private var linkMargins = true
    let onConfirm: (MarginConfig) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Image Border").font(.headline)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Margin Settings").font(.caption).foregroundColor(.secondary)
                    marginField("Top", $config.top, "arrow.up")
                    HStack(spacing: 16) {
                        marginField("Left", $config.left, "arrow.left")
                        Spacer()
                        marginField("Right", $config.right, "arrow.right")
                    }
                    marginField("Bottom", $config.bottom, "arrow.down")
                    Toggle("Link all margins", isOn: $linkMargins).font(.caption)
                }
                Toggle("If negative values used: put the border on the inside", isOn: $config.putBorderInside).font(.caption)
                ColorPickerView(title: "Border Color", selectedColor: .init(get: { AppState.backgroundColor }, set: { AppState.backgroundColor = $0 }))
            }
            
            Spacer()
            
            HStack {
                Button("Clear") { config = MarginConfig(); save() }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.escape)
                Button("Apply") { onConfirm(config) }.disabled(!config.isComplete)
                Button("OK") { onConfirm(config); onCancel() }.keyboardShortcut(.return).buttonStyle(.borderedProminent).disabled(!config.isComplete)
            }
        }
        .padding(24).frame(width: 400, height: 400)
        .onAppear { load() }
        .onChange(of: linkMargins) { _, new in if new, let v = getCommon() { [v].forEach { config.top = $0; config.bottom = $0; config.left = $0; config.right = $0 }; save() } }
        .onChange(of: config.top) { _, new in if linkMargins && !new.isEmpty { config.bottom = new; config.left = new; config.right = new; save() } }
        .onChange(of: config.top) { _, _ in save() }
        .onChange(of: config.bottom) { _, _ in save() }
        .onChange(of: config.left) { _, _ in save() }
        .onChange(of: config.right) { _, _ in save() }
        .onChange(of: config.putBorderInside) { _, _ in save() }
    }
    
    private func marginField(_ title: String, _ value: Binding<String>, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).font(.caption).foregroundColor(.secondary)
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            TextField("0", text: value).textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
    
    private func getCommon() -> String? {
        let v = [config.top, config.bottom, config.left, config.right].filter { !$0.isEmpty }
        return Set(v).count == 1 ? v.first : nil
    }
    
    private func save() {
        UserDefaults.standard.set(config.top, forKey: "mTop")
        UserDefaults.standard.set(config.bottom, forKey: "mBottom")
        UserDefaults.standard.set(config.left, forKey: "mLeft")
        UserDefaults.standard.set(config.right, forKey: "mRight")
        UserDefaults.standard.set(config.putBorderInside, forKey: "mInside")
        UserDefaults.standard.set(linkMargins, forKey: "mLink")
    }
    
    private func load() {
        config.top = UserDefaults.standard.string(forKey: "mTop") ?? ""
        config.bottom = UserDefaults.standard.string(forKey: "mBottom") ?? ""
        config.left = UserDefaults.standard.string(forKey: "mLeft") ?? ""
        config.right = UserDefaults.standard.string(forKey: "mRight") ?? ""
        config.putBorderInside = UserDefaults.standard.bool(forKey: "mInside")
        linkMargins = UserDefaults.standard.bool(forKey: "mLink")
    }
}

class MarginPanelManager {
    static let shared = MarginPanelManager()
    private var window: NSWindow?
    
    func show(onConfirm: @escaping (MarginConfig) -> Void) {
        window?.close()
        let w = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.contentView = NSHostingView(rootView: MarginPanelView(onConfirm: onConfirm, onCancel: { w.close() }))
        w.title = "Image Border Margins"
        w.center()
        w.makeKeyAndOrderFront(nil)
        w.level = .floating
        w.isReleasedWhenClosed = false
        window = w
    }
    
    func hide() { window?.close() }
}
