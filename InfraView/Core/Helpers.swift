//
//  Helpers.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Math Helpers

@inline(__always)
func clamp<T: Comparable>(_ x: T, _ r: ClosedRange<T>) -> T {
    min(max(x, r.lowerBound), r.upperBound)
}

func signedSqrt(_ v: CGFloat) -> CGFloat {
    if v > 0 {
        return sqrt(v)
    } else if v < 0 {
        return -sqrt(-v)
    } else {
        return 0
    }
}

// MARK: - ScrollView Helpers

/// 将原点限制在合法范围并处理"小图居中"的情形
func clampOrigin(_ o: NSPoint, cv: NSClipView, doc: NSView) -> NSPoint {
    var o = o
    let dw = doc.bounds.width, dh = doc.bounds.height
    let cw = cv.bounds.width, ch = cv.bounds.height
    o.x = (dw <= cw) ? (dw - cw)/2 : min(max(0, o.x), dw - cw)
    o.y = (dh <= ch) ? (dh - ch)/2 : min(max(0, o.y), dh - ch)
    return o
}

func legacyScrollbarThickness() -> (vertical: CGFloat, horizontal: CGFloat) {
    if NSScroller.preferredScrollerStyle == .overlay { return (0, 0) }
    let t = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    return (vertical: t, horizontal: t)
}


// MARK: - Image Loading Helpers

/// 从 URL 加载 CGImage，应用 EXIF 方向信息
func decodeCGImageApplyingOrientation(_ url: URL) -> (CGImage?, CGSize, String?) {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return (nil, .zero, "Unable to create image source.")
    }

    // 先取像素尺寸（不用创建整图，避免额外解码）
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as NSDictionary?
    let pxW = (props?[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
    let pxH = (props?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
    let maxDim = Int(max(pxW, pxH))

    // 用"缩略图"API但把目标尺寸设为原始最大边 + transform=true
    // 好处：ImageIO 会自动应用 EXIF 方向，不需要我们手写矩阵
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDim,
        kCGImageSourceCreateThumbnailWithTransform: true, // ✅ 应用 EXIF 方向
        kCGImageSourceShouldCache: false                  // 不提前缓存像素
    ]

    if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
        // 注意：经方向修正后，像素宽高可能互换（例如 90° 旋转）
        let outSize = CGSize(width: cg.width, height: cg.height)
        return (cg, outSize, nil)
    }
    
    // 🔁 fallback：直接拿原始 CGImage（有些 RAW/系统版本下面缩略图会失败）
    let fullOpts: [CFString: Any] = [
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldAllowFloat: true
    ]
    if let full = CGImageSourceCreateImageAtIndex(src, 0, fullOpts as CFDictionary) {
        let outSize = CGSize(width: full.width, height: full.height)
        return (full, outSize, nil)
    }

    return (nil, .zero, "Unsupported image format.")
}

/// 从 URL 加载 CGImage（带安全作用域访问）
func loadCGForURL(_ url: URL) -> (CGImage?, CGSize, String?) {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }

    guard FileManager.default.fileExists(atPath: url.path) else {
        return (nil, .zero, "File does not exist.")
    }
    guard FileManager.default.isReadableFile(atPath: url.path) else {
        return (nil, .zero, "File cannot be read.")
    }

    let (cgOpt, pixelSize, err) = decodeCGImageApplyingOrientation(url)
    return (cgOpt, pixelSize, err)
}

/// 从 NSItemProvider 异步加载 URL
func loadItemURL(provider: NSItemProvider, type: UTType) async -> URL? {
    await withCheckedContinuation { cont in
        provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
            if let url = item as? URL {
                cont.resume(returning: url)
            } else if let nsurl = item as? NSURL, let u = nsurl as URL? {
                cont.resume(returning: u)
            } else if let data = item as? Data {
                var stale = false
                if let u = try? URL(resolvingBookmarkData: data,
                                    options: [.withSecurityScope, .withoutUI],
                                    relativeTo: nil,
                                    bookmarkDataIsStale: &stale),
                   !stale {
                    cont.resume(returning: u)
                } else if type.conforms(to: .image) {
                    // ✅ 为常见图片类型兜底扩展名，避免用到 "img"
                    let ext: String = {
                        if let e = type.preferredFilenameExtension { return e }
                        if type.conforms(to: .png)  { return "png" }
                        if type.conforms(to: .jpeg) { return "jpg" }
                        if type.conforms(to: .tiff) { return "tiff" }
                        if type.conforms(to: .gif)  { return "gif" }
                        if type.conforms(to: .heic) { return "heic" }
                        if let webp = UTType("public.webp"), type.conforms(to: webp) { return "webp" }
                        return "img"
                    }()
                    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    try? data.write(to: tmp)
                    cont.resume(returning: tmp)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

