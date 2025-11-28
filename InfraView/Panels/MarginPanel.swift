//
//  MarginPanel.swift
//  InfraView
//
//  Created by 王洋 on 2025.
//

import SwiftUI
import Combine

// MARK: - 数据模型
struct MarginConfig {
    var top: String = ""
    var bottom: String = ""
    var left: String = ""
    var right: String = ""
    var putBorderInside: Bool = false
    
    // 便捷方法：获取数值（用于计算）
    func numericValues() -> (top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) {
        let topValue = CGFloat(Double(top) ?? 0)
        let bottomValue = CGFloat(Double(bottom) ?? 0)
        let leftValue = CGFloat(Double(left) ?? 0)
        let rightValue = CGFloat(Double(right) ?? 0)
        return (topValue, bottomValue, leftValue, rightValue)
    }
    
    // 检查是否所有边距都已设置
    var isComplete: Bool {
        !top.isEmpty && !bottom.isEmpty && !left.isEmpty && !right.isEmpty
    }
}

// MARK: - 面板状态管理
class MarginPanelState: ObservableObject {
    @Published var top: String = ""
    @Published var bottom: String = ""
    @Published var left: String = ""
    @Published var right: String = ""
    @Published var linkMargins: Bool = true
    @Published var putBorderInside: Bool = false
    
    static let shared = MarginPanelState()
    
    private init() {}
    
    func clearAll() {
        top = ""
        bottom = ""
        left = ""
        right = ""
        linkMargins = true
        putBorderInside = false
    }
    
    func toConfig() -> MarginConfig {
        MarginConfig(
            top: top,
            bottom: bottom,
            left: left,
            right: right,
            putBorderInside: putBorderInside
        )
    }
    
    func fromConfig(_ config: MarginConfig) {
        top = config.top
        bottom = config.bottom
        left = config.left
        right = config.right
        putBorderInside = config.putBorderInside
    }
    
    var isComplete: Bool {
        !top.isEmpty && !bottom.isEmpty && !left.isEmpty && !right.isEmpty
    }
}

// MARK: - 可复用组件
struct MarginInputField: View {
    let title: String
    @Binding var value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            TextField("0", text: $value)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

// MARK: - 主面板视图
struct MarginPanelView: View {
    @StateObject private var state = MarginPanelState.shared
    
    private var backgroundColor: Binding<Color> {
        Binding(
            get: { AppState.backgroundColor },
            set: { AppState.backgroundColor = $0 }
        )
    }
    
    let onConfirm: (MarginConfig) -> Void
    let onCancel: () -> Void
    let onOK: (MarginConfig) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Image Border")
                .font(.headline)
            
            VStack(spacing: 16) {
                // 边距输入区域
                VStack(alignment: .leading, spacing: 12) {
                    Text("Margin Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // 顶部边距
                    MarginInputField(title: "Top", value: $state.top, icon: "arrow.up")
                    
                    // 中间行：左右边距
                    HStack(spacing: 16) {
                        MarginInputField(title: "Left", value: $state.left, icon: "arrow.left")
                        Spacer()
                        MarginInputField(title: "Right", value: $state.right, icon: "arrow.right")
                    }
                    
                    // 底部边距
                    MarginInputField(title: "Bottom", value: $state.bottom, icon: "arrow.down")
                    
                    // 链接边距选项
                    Toggle("Link all margins", isOn: $state.linkMargins)
                        .font(.caption)
                        .onChange(of: state.linkMargins) { newValue in
                            if newValue, let commonValue = getCommonValue() {
                                state.top = commonValue
                                state.bottom = commonValue
                                state.left = commonValue
                                state.right = commonValue
                            }
                        }
                }
                .onChange(of: state.top) { newValue in
                    if state.linkMargins && !newValue.isEmpty {
                        state.bottom = newValue
                        state.left = newValue
                        state.right = newValue
                    }
                }
                
                // 边框位置选项
                Toggle("If negative values used: put the border on the inside", isOn: $state.putBorderInside)
                    .font(.caption)
                
                // 背景色选择
                ColorPickerView(title: "Border Color", selectedColor: backgroundColor)
            }
            
            // 按钮区域
            HStack {
                Button("Clear") {
                    state.clearAll()
                }
                
                Spacer()
                
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
                
                Button("Apply") {
                    onConfirm(state.toConfig())
                }
                .disabled(!state.isComplete)
                
                Button("OK") {
                    onOK(state.toConfig())
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!state.isComplete)
            }
        }
        .padding(20)
        .frame(width: 380, height: 320)
    }
    
    // 获取当前共同的边距值（用于链接功能）
    private func getCommonValue() -> String? {
        let values = [state.top, state.bottom, state.left, state.right].filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }
        
        // 如果所有非空值都相同，返回该值
        let uniqueValues = Set(values)
        return uniqueValues.count == 1 ? values.first : nil
    }
}

// MARK: - 面板管理器
class MarginPanelManager {
    static let shared = MarginPanelManager()
    private var panel: NSPanel?
    
    // 简化方法：使用相同的回调处理 Apply 和 OK
    func show(onConfirm: @escaping (MarginConfig) -> Void) {
        show(onConfirm: onConfirm, onOK: onConfirm)
    }
    
    // 完整方法：分别处理 Apply 和 OK
    func show(onConfirm: @escaping (MarginConfig) -> Void, onOK: @escaping (MarginConfig) -> Void) {
        if panel == nil { createPanel() }
        
        let contentView = MarginPanelView(
            onConfirm: { config in
                onConfirm(config)
                // 不隐藏面板，保持打开状态
            },
            onCancel: {
                self.hide()
            },
            onOK: { config in
                onOK(config)
                self.hide()
            }
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
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Image Border Margins"
        panel.level = .floating
        panel.center()
        panel.isReleasedWhenClosed = false
        self.panel = panel
    }
}
