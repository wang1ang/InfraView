//
//  Rotate.swift
//  InfraView
//
//  Created by 王洋 on 10/10/2025.
//
import AppKit


func rotate(_ image: NSImage, quarterTurns q: Int) -> NSImage {
    let k = ((q % 4) + 4) % 4         // 0,1,2,3
    if k == 0 { return image }

    let src = image.size
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

    image.draw(in: .init(origin: .zero, size: src), from: .zero, operation: .copy, fraction: 1)
    return out
}
