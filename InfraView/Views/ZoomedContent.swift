//
//  ZoomedContent.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import SwiftUI
import AppKit

/// 检查图片是否为动画
@inline(__always)
private func isAnimated(_ img: NSImage) -> Bool {
    img.representations.contains { ($0 as? NSBitmapImageRep)?.value(forProperty: .frameCount) as? Int ?? 0 > 1 }
}

/// 可缩放的图片内容视图
struct ZoomedContent: View {
    let width: CGFloat
    let height: CGFloat
    let image: NSImage
    
    @ViewBuilder
    private func imageView(_ w: CGFloat, _ h: CGFloat) -> some View {
        if isAnimated(image) {
            AnimatedImageView(image: image)
                .frame(width: w, height: h)
        } else {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: w, height: h)
        }
    }
    
    var body: some View {
        ZStack {
            CheckerboardBackground()
                .frame(width: width, height: height)
                .clipped()
            imageView(width, height)
        }
        .frame(width: width, height: height)
    }
}

/// 动画图片视图（使用 NSImageView）
struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage
    
    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleNone
        v.animates = true
        v.image = image
        return v
    }
    
    func updateNSView(_ v: NSImageView, context: Context) {
        if v.image !== image { v.image = image }
        if v.animates == false { v.animates = true }
    }
}

