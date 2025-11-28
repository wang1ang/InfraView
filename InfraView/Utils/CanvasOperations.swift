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
    // 解析边距
    let margins = config.numericValues()
    
    // 计算新尺寸
    let originalSize = originalImage.pixelSize
    let newWidth = originalSize.width + margins.left + margins.right
    let newHeight = originalSize.height + margins.top + margins.bottom
    let newSize = NSSize(width: newWidth, height: newHeight)
    
    // 计算位置偏移（考虑边框在内侧的情况）
    let offset = calculateBorderOffset(originalSize: originalSize, margins: margins, putBorderInside: config.putBorderInside)
    
    // 创建带边框的画布
    return createBorderedCanvas(originalImage: originalImage, newSize: newSize, offset: offset, backgroundColor: AppState.backgroundColor)
}

private func calculateBorderOffset(originalSize: NSSize, margins: (top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat), putBorderInside: Bool) -> NSPoint {
    if putBorderInside {
        // 边框在内侧：图片尺寸不变，在图片内部绘制边框
        return NSPoint(x: margins.left, y: margins.bottom)
    } else {
        // 边框在外侧：图片位置偏移，为边框留出空间
        return NSPoint(x: margins.left, y: margins.bottom)
    }
}

private func createBorderedCanvas(originalImage: LoadedImage, newSize: NSSize, offset: NSPoint, backgroundColor: Color) -> CGImage? {
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
    
    // 填充背景色（边框颜色）
    let nsColor = NSColor(backgroundColor)
    ctx.setFillColor(nsColor.cgColor)
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

// 在 MarginConfig 中添加数值转换方法
extension MarginConfig {
    func numericValues() -> (top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) {
        return (CGFloat(Double(top) ?? 0),
                CGFloat(Double(bottom) ?? 0),
                CGFloat(Double(left) ?? 0),
                CGFloat(Double(right) ?? 0))
    }
}
