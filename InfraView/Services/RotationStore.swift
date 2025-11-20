//
//  RotationStore.swift
//  InfraView
//
//  Created by 王洋 on 10/10/2025.
//

import Foundation

final class RotationStore {
    static let shared = RotationStore()
    private let defaults = UserDefaults.standard
    private let prefix = "rot:"   // rot:<volUUID>::<fileID> -> Int(0~3)

    private func key(for url: URL) -> String {
        let rv = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeUUIDStringKey])
        if let fid = rv?.fileResourceIdentifier, let vol = rv?.volumeUUIDString {
            return "\(prefix)\(vol)::\(fid)"
        }
        // 兜底：用绝对路径（移动/改名会失效，但至少可用）
        return "\(prefix)\(url.path)"
    }

    func get(for url: URL) -> Int {
        let k = key(for: url)
        // 未设置时 integer(forKey:) 返回 0，正好是"无旋转"
        return defaults.integer(forKey: k) % 4
    }

    func set(_ q: Int, for url: URL) {
        let v = ((q % 4) + 4) % 4
        defaults.set(v, forKey: key(for: url))
    }
}

