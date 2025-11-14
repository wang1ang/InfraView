//
//  VM+Erase.swift
//  InfraView
//
//  Created by 王洋 on 14/11/2025.
//

import AppKit

extension NSImage {
    var cgImageSafe: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

extension ViewerViewModel {
    func eraseSelection() {
        guard let rectPx = selectionRectPx,
              rectPx.width > 0, rectPx.height > 0
        else { return }

        guard let srcImage = processedImage,
              let cg = srcImage.cgImageSafe
        else { return }

        let width  = cg.width
        let height = cg.height

        guard let colorSpace = cg.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: cg.bitsPerComponent,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: cg.bitmapInfo.rawValue
              ) else { return }

        // 先画原图
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // ⚠️ 坐标转换：你的 selectionRectPx 是“像素 + 左上原点”，
        // CoreGraphics 是“像素 + 左下原点”
        let eraseRect = CGRect(
            x: rectPx.minX,
            y: CGFloat(height) - rectPx.maxY,
            width: rectPx.width,
            height: rectPx.height
        )

        // 用 clear 擦成透明（如果图像本身没 alpha，可改成填白色）
        ctx.clear(eraseRect)

        guard let newCG = ctx.makeImage() else { return }

        let newNSImage = NSImage(cgImage: newCG, size: srcImage.size)

        DispatchQueue.main.async {
            self.processedImage = newNSImage
            self.selectionRectPx = nil   // 清掉选区
            // 如果你有别的地方依赖选区变化，这里可以发通知或调用回调
        }
    }
}
