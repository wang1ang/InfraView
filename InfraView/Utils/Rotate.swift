//
//  Rotate.swift
//  InfraView
//
//  Created by 王洋 on 10/10/2025.
//
import AppKit

func rotate(_ image: LoadedImage, quarterTurns q: Int) -> LoadedImage {
    print("rotate: \(q)")
    let k = ((q % 4) + 4) % 4
    if k == 0 { return image }
    
    let srcSize = image.pixelSize
    let dstSize = (k % 2 == 0) ? srcSize : NSSize(width: srcSize.height, height: srcSize.width)
    
    // 获取源图像的 CGImage
    guard let cgImage = image.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
    
    // 创建目标位图上下文（精确像素尺寸）
    let width = Int(dstSize.width)
    let height = Int(dstSize.height)
    
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return image }
    
    // 不插值
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)
    
    // 应用变换
    switch k {
    case 1: // 右转 90°（顺时针）
        ctx.translateBy(x: 0, y: dstSize.height)
        ctx.rotate(by: -.pi / 2)
    case 2: // 180°
        ctx.translateBy(x: dstSize.width, y: dstSize.height)
        ctx.rotate(by: .pi)
    case 3: // 左转 90°（逆时针）
        ctx.translateBy(x: dstSize.width, y: 0)
        ctx.rotate(by: .pi / 2)
    default:
        break
    }

    // 绘制源图像
    let drawRect = CGRect(x: 0, y: 0, width: srcSize.width, height: srcSize.height)
    ctx.draw(cgImage, in: drawRect)
    // 从上下文创建 CGImage
    guard let rotatedCGImage = ctx.makeImage() else { return image }
    // 创建 NSImage
    let out = NSImage(cgImage: rotatedCGImage, size: dstSize)
    return LoadedImage(image: out, pixelSize: dstSize)
}
// 公共的图片变换函数
private func transformCGImage(_ image: NSImage, transform: CGAffineTransform) -> CGImage? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }

    let width = Int(cgImage.width)
    let height = Int(cgImage.height)

    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return cgImage }

    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)
    ctx.concatenate(transform)
    ctx.draw(cgImage, in: CGRect(origin: .zero, size: CGSize(width: CGFloat(width), height: CGFloat(height))))

    guard let transformedCGImage = ctx.makeImage() else { return cgImage }
    return transformedCGImage
}

// 水平翻转
func flipHorizontally(_ image: LoadedImage) -> CGImage? {
    let transform = CGAffineTransform(scaleX: -1, y: 1)
        .translatedBy(x: -image.pixelSize.width, y: 0)
    return transformCGImage(image.image, transform: transform)
}

// 垂直翻转
func flipVertically(_ image: LoadedImage) -> CGImage? {
    let transform = CGAffineTransform(scaleX: 1, y: -1)
        .translatedBy(x: 0, y: -image.pixelSize.height)
    return transformCGImage(image.image, transform: transform)
}
