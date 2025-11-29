//
//  CanvasOperations.swift
//  InfraView
//
//  Created by 王洋 on 2025.
//

import SwiftUI

// MARK: - 画布操作函数
func changeCanvasSize(originalImage: LoadedImage, config: CanvasSizeConfig) -> CGImage? {
    // 解析尺寸
    guard let newWidth = Int(config.width), let newHeight = Int(config.height),
          newWidth > 0, newHeight > 0 else {
        print("Invalid canvas size: \(config.width)x\(config.height)")
        return nil
    }
    
    let originalSize = originalImage.pixelSize
    let newSize = NSSize(width: newWidth, height: newHeight)
    
    // 计算位置偏移
    let offset = calculateOffset(originalSize: originalSize, newSize: newSize, alignment: config.alignment)
    
    // 创建新的画布
    return createNewCanvas(originalImage: originalImage, newSize: newSize, offset: offset, backgroundColor: AppState.backgroundColor)
}

private func calculateOffset(originalSize: NSSize, newSize: NSSize, alignment: CanvasAlignment) -> NSPoint {
    let dx = newSize.width - originalSize.width
    let dy = newSize.height - originalSize.height
    
    switch alignment {
    case .topLeft:
        return NSPoint(x: 0, y: dy)
    case .top:
        return NSPoint(x: dx / 2, y: dy)
    case .topRight:
        return NSPoint(x: dx, y: dy)
    case .left:
        return NSPoint(x: 0, y: dy / 2)
    case .center:
        return NSPoint(x: dx / 2, y: dy / 2)
    case .right:
        return NSPoint(x: dx, y: dy / 2)
    case .bottomLeft:
        return NSPoint(x: 0, y: 0)
    case .bottom:
        return NSPoint(x: dx / 2, y: 0)
    case .bottomRight:
        return NSPoint(x: dx, y: 0)
    }
}

private func createNewCanvas(originalImage: LoadedImage, newSize: NSSize, offset: NSPoint, backgroundColor: Color) -> CGImage? {
    guard let cgImage = originalImage.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }
    
    let width = Int(newSize.width)
    let height = Int(newSize.height)
    
    // 创建位图上下文
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    
    // 设置不插值
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)
    
    // 填充背景色 - 修复这里
    let nsColor = NSColor(backgroundColor)
    ctx.setFillColor(nsColor.cgColor) // 直接使用，不需要 if let
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    // 绘制原图像
    let drawRect = CGRect(
        x: offset.x,
        y: offset.y,
        width: originalImage.pixelSize.width,
        height: originalImage.pixelSize.height
    )
    ctx.draw(cgImage, in: drawRect)
    
    // 创建新图像
    guard let newCGImage = ctx.makeImage() else {
        return nil
    }
    return newCGImage
}












// MARK: - 边框操作函数
func addBorderToImage(originalImage: LoadedImage, config: MarginConfig) -> CGImage? {
    let top = CGFloat(Double(config.top) ?? 0)
    let bottom = CGFloat(Double(config.bottom) ?? 0)
    let left = CGFloat(Double(config.left) ?? 0)
    let right = CGFloat(Double(config.right) ?? 0)
    
    let originalSize = originalImage.pixelSize
    
    if config.putBorderInside {
        // 选框选中：正值=外侧边框，负值=内侧边框
        return createBorderWithNegativeInside(originalImage: originalImage, top: top, bottom: bottom, left: left, right: right, borderColor: AppState.backgroundColor)
    } else {
        // 选框未选中：正值=外侧边框，负值=裁剪
        return createBorderWithNegativeCrop(originalImage: originalImage, top: top, bottom: bottom, left: left, right: right, borderColor: AppState.backgroundColor)
    }
}

private func createBorderWithNegativeInside(originalImage: LoadedImage, top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat, borderColor: Color) -> CGImage? {
    guard let cgImage = originalImage.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }
    
    let originalSize = originalImage.pixelSize
    
    // 计算新尺寸：正值扩展，负值不扩展
    let newWidth = originalSize.width + max(left, 0) + max(right, 0)
    let newHeight = originalSize.height + max(top, 0) + max(bottom, 0)
    let newSize = NSSize(width: newWidth, height: newHeight)
    
    let width = Int(newSize.width)
    let height = Int(newSize.height)
    
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)
    
    // 填充背景色
    let nsColor = NSColor(borderColor)
    ctx.setFillColor(nsColor.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    // 绘制原图（考虑正值偏移）
    let drawRect = CGRect(
        x: max(left, 0),
        y: max(bottom, 0),
        width: originalSize.width,
        height: originalSize.height
    )
    ctx.draw(cgImage, in: drawRect)
    
    // 在图片上绘制负值边距的内侧边框
    ctx.setFillColor(nsColor.cgColor)
    
    // 只处理负值：在图片内部绘制边框
    if top < 0 {
        let borderHeight = abs(top)
        ctx.fill(CGRect(
            x: max(left, 0),
            y: max(bottom, 0) + originalSize.height - borderHeight,
            width: originalSize.width,
            height: borderHeight
        ))
    }
    if bottom < 0 {
        let borderHeight = abs(bottom)
        ctx.fill(CGRect(
            x: max(left, 0),
            y: max(bottom, 0),
            width: originalSize.width,
            height: borderHeight
        ))
    }
    if left < 0 {
        let borderWidth = abs(left)
        ctx.fill(CGRect(
            x: max(left, 0),
            y: max(bottom, 0),
            width: borderWidth,
            height: originalSize.height
        ))
    }
    if right < 0 {
        let borderWidth = abs(right)
        ctx.fill(CGRect(
            x: max(left, 0) + originalSize.width - borderWidth,
            y: max(bottom, 0),
            width: borderWidth,
            height: originalSize.height
        ))
    }
    
    return ctx.makeImage()
}

private func createBorderWithNegativeCrop(originalImage: LoadedImage, top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat, borderColor: Color) -> CGImage? {
    // 选框未选中：正值扩展，负值裁剪
    let originalSize = originalImage.pixelSize
    
    // 计算新尺寸（正值扩展，负值裁剪）
    let newWidth = originalSize.width + left + right
    let newHeight = originalSize.height + top + bottom
    
    // 如果尺寸无效，返回nil
    guard newWidth > 0 && newHeight > 0 else {
        return nil
    }
    
    let newSize = NSSize(width: newWidth, height: newHeight)
    
    // 计算裁剪后的绘制区域
    let drawRect = CGRect(
        x: max(-left, 0),      // 负值left表示从左边裁剪
        y: max(-bottom, 0),    // 负值bottom表示从下边裁剪
        width: originalSize.width + min(left, 0) + min(right, 0),  // 减去裁剪的部分
        height: originalSize.height + min(top, 0) + min(bottom, 0)
    )
    
    guard let cgImage = originalImage.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let croppedImage = cgImage.cropping(to: drawRect) else {
        return nil
    }
    
    // 创建新的画布
    let width = Int(newSize.width)
    let height = Int(newHeight)
    
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)
    
    // 填充背景色
    let nsColor = NSColor(borderColor)
    ctx.setFillColor(nsColor.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    // 绘制裁剪后的图片
    let finalDrawRect = CGRect(
        x: max(left, 0),
        y: max(bottom, 0),
        width: drawRect.width,
        height: drawRect.height
    )
    ctx.draw(croppedImage, in: finalDrawRect)
    
    return ctx.makeImage()
}
