//
//  CanvasSizePanel.swift
//  InfraView
//
//  Created by 王洋 on 24/11/2025.
//


import SwiftUI

// MARK: - 数据模型
struct CanvasSizeConfig {
    var width: String = ""
    var height: String = ""
    var alignment: CanvasAlignment = .center
}

enum CanvasAlignment: String, CaseIterable, Identifiable {
    case top = "Top", bottom = "Bottom", left = "Left", right = "Right", center = "Center"
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .top: return "arrow.up.square"
        case .bottom: return "arrow.down.square"
        case .left: return "arrow.left.square"
        case .right: return "arrow.right.square"
        case .center: return "square"
        }
    }
}

// MARK: - 主面板视图
struct CanvasSizePanelView: View {
    @State private var width: String = ""
    @State private var height: String = ""
    @State private var alignment: CanvasAlignment = .center
    let onConfirm: (CanvasSizeConfig) -> Void
    let onCancel: () -> Void
    
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
                
                // 对齐方式选择
                VStack(alignment: .leading) {
                    Text("Alignment").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        ForEach(CanvasAlignment.allCases) { align in
                            Button(action: { alignment = align }) {
                                VStack(spacing: 4) {
                                    Image(systemName: align.systemImage).font(.title3)
                                    Text(align.rawValue).font(.caption2)
                                }
                                .foregroundColor(alignment == align ? .accentColor : .primary)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(alignment == align ? Color.accentColor.opacity(0.1) : Color.clear)
                                )
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            
            // 按钮
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.escape)
                Button("Apply") {
                    onConfirm(CanvasSizeConfig(width: width, height: height, alignment: alignment))
                }.keyboardShortcut(.return).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
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
        panel?.orderOut(nil)
    }
    
    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
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
