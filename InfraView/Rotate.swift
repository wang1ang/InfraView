//
//  Rotate.swift
//  InfraView
//
//  Created by 王洋 on 10/10/2025.
//
import AppKit


func rotate(_ image: LoadedImage, quarterTurns q: Int) -> LoadedImage {
    let k = ((q % 4) + 4) % 4         // 0,1,2,3
    if k == 0 { return image }

    let src = image.image.size
    let dst = (k % 2 == 0) ? src : NSSize(width: src.height, height: src.width)

    let out = NSImage(size: dst)
    out.lockFocus(); defer { out.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    switch k {
    case 1: // 右转 90°（顺时针）
        ctx.translateBy(x: 0, y: dst.height)   // = src.width
        ctx.rotate(by: -.pi / 2)
    case 2: // 180°
        ctx.translateBy(x: dst.width, y: dst.height)
        ctx.rotate(by: .pi)
    case 3: // 左转 90°（逆时针）
        ctx.translateBy(x: dst.width, y: 0)    // = src.height
        ctx.rotate(by: .pi / 2)
    default:
        break
    }

    image.image.draw(in: .init(origin: .zero, size: src), from: .zero, operation: .copy, fraction: 1)
    return LoadedImage(image: out, pixelSize: dst)
}


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
        // 未设置时 integer(forKey:) 返回 0，正好是“无旋转”
        return defaults.integer(forKey: k) % 4
    }

    func set(_ q: Int, for url: URL) {
        let v = ((q % 4) + 4) % 4
        defaults.set(v, forKey: key(for: url))
    }
}
