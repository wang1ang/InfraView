//
//  StarStore.swift
//  InfraView
//
//  Created by 王洋 on 23/11/2025.
//

import Foundation

final class StarStore {
    static let shared = StarStore()
    private let defaults = UserDefaults.standard
    private let prefix = "star:"   // star:<volUUID>::<fileID> -> Bool

    private func key(for url: URL) -> String {
        let rv = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeUUIDStringKey])
        if let fid = rv?.fileResourceIdentifier, let vol = rv?.volumeUUIDString {
            return "\(prefix)\(vol)::\(fid)"
        }
        // 兜底：用绝对路径（移动/改名会失效，但至少可用）
        return "\(prefix)\(url.path)"
    }

    func get(for url: URL) -> Bool {
        let k = key(for: url)
        // 未设置时 bool(forKey:) 返回 false，正好是"未加星标"
        return defaults.bool(forKey: k)
    }

    func set(_ starred: Bool, for url: URL) {
        defaults.set(starred, forKey: key(for: url))
    }

    func toggle(for url: URL) -> Bool {
        let newValue = !get(for: url)
        set(newValue, for: url)
        return newValue
    }
}
