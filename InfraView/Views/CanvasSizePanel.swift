//
//  CanvasSizePanel.swift
//  InfraView
//
//  Created by 王洋 on 2025.
//

import SwiftUI

// MARK: - 数据模型
struct CanvasSizeConfig {
    var width: String = ""
    var height: String = ""
    var alignment: CanvasAlignment = .center
    var backgroundColor: Color = .black
}

enum CanvasAlignment: String, CaseIterable, Identifiable {
    case topLeft = "Top Left"
    case top = "Top"
    case topRight = "Top Right"
    case left = "Left"
    case center = "Center"
    case right = "Right"
    case bottomLeft = "Bottom Left"
    case bottom = "Bottom"
    case bottomRight = "Bottom Right"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .topLeft: return "arrow.up.left.square"
        case .top: return "arrow.up.square"
        case .topRight: return "arrow.up.right.square"
        case .left: return "arrow.left.square"
        case .center: return "square"
        case .right: return "arrow.right.square"
        case .bottomLeft: return "arrow.down.left.square"
        case .bottom: return "arrow.down.square"
        case .bottomRight: return "arrow.down.right.square"
        }
    }
}

// MARK: - 可复用组件
struct ColorPickerView: View {
    let title: String
    @Binding var selectedColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 60, height: 30)
            }
        }
    }
}

// MARK: - 主面板视图
struct CanvasSizePanelView: View {
    @State private var width: String = ""
    @State private var height: String = ""
    @State private var alignment: CanvasAlignment = .center
    @State private var backgroundColor: Color = .black
    let onConfirm: (CanvasSizeConfig) -> Void
    let onCancel: () -> Void
    
    // 3x3 grid arrangement
    private let alignmentRows: [[CanvasAlignment]] = [
        [.topLeft, .top, .topRight],
        [.left, .center, .right],
        [.bottomLeft, .bottom, .bottomRight]
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Change Canvas Size").font(.headline)
            
            VStack(spacing: 16) {
                // 尺寸输入
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Width").font(.caption).foregroundColor(.secondary)
                        TextField("Width", text: $width).textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    VStack(alignment: .leading) {
                        Text("Height").font(.caption).foregroundColor(.secondary)
                        TextField("Height", text: $height).textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                // 3x3 grid alignment selector
                VStack(alignment: .leading) {
                    Text("Alignment").font(.caption).foregroundColor(.secondary)
                    VStack(spacing: 8) {
                        ForEach(alignmentRows, id: \.self) { row in
                            HStack(spacing: 8) {
                                ForEach(row) { align in
                                    Button(action: { alignment = align }) {
                                        VStack(spacing: 4) {
                                            Image(systemName: align.systemImage).font(.title3)
                                            Text(align.rawValue)
                                                .font(.system(size: 9))
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .foregroundColor(alignment == align ? .accentColor : .primary)
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(alignment == align ? Color.accentColor.opacity(0.1) : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .focusable(false)
                                }
                            }
                        }
                    }
                }
                // 背景色选择
                ColorPickerView(title: "Background Color", selectedColor: $backgroundColor)
            }
            
            // 按钮
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.escape)
                Button("Apply") {
                    onConfirm(CanvasSizeConfig(
                        width: width,
                        height: height,
                        alignment: alignment,
                        backgroundColor: backgroundColor
                    ))
                }.keyboardShortcut(.return).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420, height: 400)
    }
}

// MARK: - 面板管理器
class CanvasSizePanelManager {
    static let shared = CanvasSizePanelManager()
    private var panel: NSPanel?
    
    func show(onConfirm: @escaping (CanvasSizeConfig) -> Void) {
        if panel == nil { createPanel() }
        
        let contentView = CanvasSizePanelView(
            onConfirm: { config in
                onConfirm(config)
                self.hide()
            },
            onCancel: { self.hide() }
        )
        
        panel?.contentView = NSHostingView(rootView: contentView)
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hide() {
        NSColorPanel.shared.orderOut(nil)
        panel?.orderOut(nil)
    }
    
    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Canvas Size"
        panel.level = .floating
        panel.center()
        self.panel = panel
    }
}
