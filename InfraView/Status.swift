// StatusBar.swift
import SwiftUI
import Combine

public struct StatusItem: Identifiable, Equatable {
    public let id = UUID()
    public var label: String
    public var value: String
}

@MainActor
public final class StatusBarStore: ObservableObject {
    public static let shared = StatusBarStore()
    @Published public var items: [StatusItem] = []
    @Published public var isVisible: Bool = true
    public var height: CGFloat { isVisible ? 22 : 0 }

    /// 设置或更新一个段位（同 label 会被覆盖）
    public func set(_ label: String, _ value: String) {
        if let i = items.firstIndex(where: { $0.label == label }) {
            items[i].value = value
        } else {
            items.append(StatusItem(label: label, value: value))
        }
    }
    public func remove(_ label: String) { items.removeAll { $0.label == label } }
    public func clear() { items.removeAll() }
}

public struct StatusBar: View {
    @ObservedObject private var store = StatusBarStore.shared

    public init() {}
    public var body: some View {
        HStack(spacing: 10) {
            ForEach(store.items) { item in
                HStack(spacing: 4) {
                    Text(item.label).foregroundStyle(.secondary)
                    Text(item.value).fontWeight(.semibold)
                }
                if item.id != store.items.last?.id {
                    Divider().frame(height: 12)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.ultraThinMaterial)     // macOS 窗口栏风格
    }
}
