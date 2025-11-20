//
//  VM+Selection.swift
//  InfraView
//
//  Created by 王洋 on 15/11/2025.
//

import AppKit

extension ViewerViewModel {
    private var activeSelectionRectPx: CGRect? {
        guard
            window?.isKeyWindow == true,          // 只响应当前 key window
            let r = selectionRectPx,
            r.width  > 0,
            r.height > 0
        else { return nil }
        return r
    }
    private var activeCGImage: CGImage? {
        if let cg = currentCGImage { return cg }
        if let img = processedImage, let cg = img.cgImageSafe {
            currentCGImage = cg
            return cg
        }
        return nil
    }
    private func croppedImage(from rect: CGRect) -> CGImage? {
        guard let cg = activeCGImage else { return nil }
        return cg.cropping(to: rect)
    }
    // ✅ 复制当前选区到剪贴板（如果有选区且有图像）
    @discardableResult
    func copySelectionToPasteboard() -> Bool{
        guard
            let rectPx = activeSelectionRectPx,
            let cropped = croppedImage(from: rectPx)
        else { return false }

        let subImage = NSImage(cgImage: cropped, size: .zero)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([subImage])
        return true
    }
    @discardableResult
    func cropSelection() -> Bool {
        guard
            let rectPx = activeSelectionRectPx,
            let cropped = croppedImage(from: rectPx)
        else { return false }

        // 3. 撤销栈
        pushUndoSnapshot()

        DispatchQueue.main.async {
            self.applyImage(cropped)
            // will be done in coordinator:
            //self.selectionRectPx = nil
        }
        return true
    }
    @discardableResult
    func eraseSelection() -> Bool {
        guard let rectPx = activeSelectionRectPx else { return false }
        guard let cg = activeCGImage else { return false }

        pushUndoSnapshot()
        
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
              ) else { return false }

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

        guard let newCG = ctx.makeImage() else { return false }

        DispatchQueue.main.async {
            self.applyImage(newCG)
            // 清不掉
            //self.selectionRectPx = nil
            // 如果你有别的地方依赖选区变化，这里可以发通知或调用回调
        }
        return true
    }
    public func colorAtPixel(x: Int, y: Int) -> NSColor? {
        guard let image = processedImage else { return nil }
        // 把 NSImage 转成 CGImage
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }

        // 用 CGImage 创建一个 bitmap rep
        let rep = NSBitmapImageRep(cgImage: cg)

        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0, h > 0 else { return nil }

        let cx = min(max(0, x), w - 1)
        let cy = min(max(0, y), h - 1)      // 如果发现上下颠倒，再改成 h - 1 - …

        return rep.colorAt(x: cx, y: cy)
    }
}
