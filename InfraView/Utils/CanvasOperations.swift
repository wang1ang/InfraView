//
//  CanvasOperations.swift
//  InfraView
//
//  Created by 王洋 on 2025.
//

import SwiftUI

// MARK: - 公共工具函数
private func _createCGContext(width: Int, height: Int) -> CGContext? {
    return CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

private func _setupContext(_ ctx: CGContext) {
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)
}

private func _getCGImage(from loadedImage: LoadedImage) -> CGImage? {
    return loadedImage.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

private func _fillBackground(_ ctx: CGContext, width: Int, height: Int, color: Color) {
    let nsColor = NSColor(color)
    ctx.setFillColor(nsColor.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
}

// MARK: - 画布操作函数
func changeCanvasSize(originalImage: LoadedImage, config: CanvasSizeConfig) -> CGImage? {
    guard let newWidth = Int(config.width), let newHeight = Int(config.height),
          newWidth > 0, newHeight > 0 else {
        print("Invalid canvas size: \(config.width)x\(config.height)")
        return nil
    }
    
    let originalSize = originalImage.pixelSize
    let newSize = NSSize(width: newWidth, height: newHeight)
    
    let offset = _calculateOffset(originalSize: originalSize, newSize: newSize, alignment: config.alignment)
    
    return _createNewCanvas(
        originalImage: originalImage,
        newSize: newSize,
        offset: offset,
        backgroundColor: AppState.backgroundColor
    )
}

private func _calculateOffset(originalSize: NSSize, newSize: NSSize, alignment: CanvasAlignment) -> NSPoint {
    let dx = newSize.width - originalSize.width
    let dy = newSize.height - originalSize.height
    
    switch alignment {
    case .topLeft:      return NSPoint(x: 0, y: dy)
    case .top:          return NSPoint(x: dx / 2, y: dy)
    case .topRight:     return NSPoint(x: dx, y: dy)
    case .left:         return NSPoint(x: 0, y: dy / 2)
    case .center:       return NSPoint(x: dx / 2, y: dy / 2)
    case .right:        return NSPoint(x: dx, y: dy / 2)
    case .bottomLeft:   return NSPoint(x: 0, y: 0)
    case .bottom:       return NSPoint(x: dx / 2, y: 0)
    case .bottomRight:  return NSPoint(x: dx, y: 0)
    }
}

private func _createNewCanvas(originalImage: LoadedImage, newSize: NSSize, offset: NSPoint, backgroundColor: Color) -> CGImage? {
    let width = Int(newSize.width)
    let height = Int(newSize.height)
    
    guard let ctx = _createCGContext(width: width, height: height),
          let cgImage = _getCGImage(from: originalImage) else {
        return nil
    }
    
    _setupContext(ctx)
    _fillBackground(ctx, width: width, height: height, color: backgroundColor)
    
    let drawRect = CGRect(
        x: offset.x,
        y: offset.y,
        width: originalImage.pixelSize.width,
        height: originalImage.pixelSize.height
    )
    ctx.draw(cgImage, in: drawRect)
    
    return ctx.makeImage()
}

// MARK: - 边框操作函数（统一版本）
func addBorderToImage(originalImage: LoadedImage, config: MarginConfig) -> CGImage? {
    let top = CGFloat(Double(config.top) ?? 0)
    let bottom = CGFloat(Double(config.bottom) ?? 0)
    let left = CGFloat(Double(config.left) ?? 0)
    let right = CGFloat(Double(config.right) ?? 0)
    
    return _createBorderedImage(
        originalImage: originalImage,
        top: top,
        bottom: bottom,
        left: left,
        right: right,
        isInsideBorder: config.putBorderInside
    )
}

private func _createBorderedImage(originalImage: LoadedImage, top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat, isInsideBorder: Bool) -> CGImage? {
    let originalSize = originalImage.pixelSize
    
    // 计算新尺寸和图像位置
    let (newSize, imageRect, cropRect) = _calculateLayout(
        originalSize: originalSize,
        top: top,
        bottom: bottom,
        left: left,
        right: right,
        isInsideBorder: isInsideBorder
    )
    
    // 验证尺寸
    guard newSize.width > 0, newSize.height > 0,
          let cgImage = _getCGImage(from: originalImage) else {
        return nil
    }
    
    // 处理图像（裁剪或直接使用）
    let finalImage: CGImage?
    if let cropRect = cropRect {
        finalImage = cgImage.cropping(to: cropRect)
    } else {
        finalImage = cgImage
    }
    
    guard let imageToDraw = finalImage,
          let ctx = _createCGContext(width: Int(newSize.width), height: Int(newSize.height)) else {
        return nil
    }
    
    _setupContext(ctx)
    _fillBackground(ctx, width: Int(newSize.width), height: Int(newSize.height), color: AppState.backgroundColor)
    
    // 绘制图像
    ctx.draw(imageToDraw, in: imageRect)
    
    // 如果是内侧边框模式，绘制内侧边框
    if isInsideBorder {
        _drawInsideBorders(ctx: ctx, imageRect: imageRect, top: top, bottom: bottom, left: left, right: right)
    }
    
    return ctx.makeImage()
}

private func _calculateLayout(originalSize: NSSize, top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat, isInsideBorder: Bool) -> (newSize: NSSize, imageRect: CGRect, cropRect: CGRect?) {
    
    if isInsideBorder {
        // 内侧边框模式：正值扩展画布，负值在图像内部绘制边框
        let newWidth = originalSize.width + max(left, 0) + max(right, 0)
        let newHeight = originalSize.height + max(top, 0) + max(bottom, 0)
        
        let imageRect = CGRect(
            x: max(left, 0),
            y: max(bottom, 0),
            width: originalSize.width,
            height: originalSize.height
        )
        
        return (NSSize(width: newWidth, height: newHeight), imageRect, nil)
    } else {
        // 外侧边框模式：正值扩展画布，负值裁剪图像
        let newWidth = originalSize.width + left + right
        let newHeight = originalSize.height + top + bottom
        
        let cropRect = CGRect(
            x: max(-left, 0),
            y: max(-bottom, 0),
            width: originalSize.width + min(left, 0) + min(right, 0),
            height: originalSize.height + min(top, 0) + min(bottom, 0)
        )
        
        let imageRect = CGRect(
            x: max(left, 0),
            y: max(bottom, 0),
            width: cropRect.width,
            height: cropRect.height
        )
        
        return (NSSize(width: newWidth, height: newHeight), imageRect, cropRect)
    }
}

private func _drawInsideBorders(ctx: CGContext, imageRect: CGRect, top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) {
    let nsColor = NSColor(AppState.backgroundColor)
    ctx.setFillColor(nsColor.cgColor)
    
    // 定义边框类型
    typealias BorderInfo = (value: CGFloat, isVertical: Bool, isTopOrLeft: Bool)
    
    let borders: [BorderInfo] = [
        (value: top, isVertical: true, isTopOrLeft: true),     // 上边框
        (value: bottom, isVertical: true, isTopOrLeft: false), // 下边框
        (value: left, isVertical: false, isTopOrLeft: true),   // 左边框
        (value: right, isVertical: false, isTopOrLeft: false)  // 右边框
    ]
    
    for border in borders {
        guard border.value < 0 else { continue }
        
        let borderSize = abs(border.value)
        var rect: CGRect
        
        if border.isVertical {
            // 上下边框
            let y = border.isTopOrLeft ? imageRect.maxY - borderSize : imageRect.minY
            rect = CGRect(x: imageRect.minX, y: y, width: imageRect.width, height: borderSize)
        } else {
            // 左右边框
            let x = border.isTopOrLeft ? imageRect.minX : imageRect.maxX - borderSize
            rect = CGRect(x: x, y: imageRect.minY, width: borderSize, height: imageRect.height)
        }
        
        ctx.fill(rect)
    }
}
