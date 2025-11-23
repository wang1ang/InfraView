// StatusBar.swift
import SwiftUI
import Combine
import ImageIO
import CoreGraphics


@MainActor
public final class StatusBarStore: ObservableObject {
    public static let shared = StatusBarStore()
    
    // UI监听的ObservableObject字段
    @Published public var pixelWidth: Int?
    @Published public var pixelHeight: Int?
    @Published public var bitsPerPixel: Int?
    @Published public var index: Int?
    @Published public var total: Int?
    @Published public var zoomPercent: Int?
    @Published public var timestamp: Date?
    @Published public var isStarred: Bool = false
    @Published public var isVisible: Bool = true

    // used for setting star
    private var activeURL: URL?

    public var height: CGFloat { isVisible ? 22 : 0 }

    // 计算出的片段（按你截图的顺序）
    public var segments: [String] {
        var s: [String] = []

        if isStarred {
            s.append("⭐")
        }

        if let w = pixelWidth, let h = pixelHeight, let bpp = bitsPerPixel {
            s.append("\(w) × \(h) × \(bpp) BPP")
        } else if let w = pixelWidth, let h = pixelHeight {
            s.append("\(w) × \(h)")
        }

        if let i = index, let t = total, t > 0 {
            s.append("\(i)/\(t)")
        }

        if let z = zoomPercent {
            s.append("\(z) %")
        }

        if let dt = timestamp {
            s.append(Self.dateFormatter.string(from: dt))
            s.append(Self.timeFormatter.string(from: dt))
        }
        return s
    }
    // 便捷设置方法（随用随调）
    public func setImageInfo(width: Int?, height: Int?, bpp: Int?) {
        pixelWidth = width; pixelHeight = height; bitsPerPixel = bpp
    }
    public func setPage(index: Int?, total: Int?) {
        self.index = index; self.total = total
    }
    public func setZoom(percent: Int?) { zoomPercent = percent }
    public func setTimestamp(_ date: Date?) { timestamp = date }
    public func toggleStar() {
        guard let url = activeURL else { return }
        let newState = StarStore.shared.toggle(for: url)
        isStarred = newState
    }

    public func clear() {
        pixelWidth = nil; pixelHeight = nil; bitsPerPixel = nil
        index = nil; total = nil; zoomPercent = nil
        timestamp = nil
        isStarred = false
        activeURL = nil
    }

    // 辅助属性和方法
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"       // 例：4/7/2025
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"       // 例：22:19:34
        return f
    }()
    
    // Viewer 内部加：更新状态栏固定字段
    public func updateStatus(url: URL, image: NSImage, index: Int, total: Int) {
        activeURL = url

        // 1) 像素尺寸与 BPP
        let (pw, ph, repBPP) = pixelInfo(from: image)
        
        //let metaBPP = bitDepthFromMetadata(url: url)
        //let bpp = metaBPP ?? repBPP
        let bpp = repBPP
        
        setImageInfo(width: pw, height: ph, bpp: bpp)

        // 2) 页码（注意 UI 从 1 开始）
        setPage(index: index + 1, total: total)

        // 3) 文件时间（创建时间优先，其次修改时间）
        if let d = fileTimestamp(url) {
            setTimestamp(d)
        } else {
            setTimestamp(nil)
        }

        isStarred = StarStore.shared.get(for: url)
    }
}

public struct StatusBar: View {
    @EnvironmentObject private var store: StatusBarStore

    public init() {}
    public var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(store.segments.enumerated()), id: \.offset) { idx, seg in
                Text(seg).fontWeight(.semibold)
                if idx != store.segments.count - 1 {
                    Divider().frame(height: 12)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.ultraThinMaterial)     // macOS 窗口栏风格
    }
}


// 提取像素宽高与 BPP
public func pixelInfo(from image: NSImage) -> (Int?, Int?, Int?) {
    // 取最大的 bitmap 表示（像素最完整）
    if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep })
        .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }) {
        return (rep.pixelsWide, rep.pixelsHigh, rep.bitsPerPixel)
    }
    if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        return (cg.width, cg.height, cg.bitsPerPixel > 0 ? cg.bitsPerPixel : nil)
    }
    // 没有 bitmap 表示时，fall back 到 size（点），无法给出 BPP
    let w = Int(image.size.width)
    let h = Int(image.size.height)
    return (w, h, nil)
}

// 读取文件的创建/修改时间
public func fileTimestamp(_ url: URL) -> Date? {
    let rv = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
    return rv?.creationDate ?? rv?.contentModificationDate
}



/// 从文件元数据/EXIF 推断位深（返回 bits-per-pixel）
func bitDepthFromMetadata(url: URL) -> Int? {
    let opts: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let src = CGImageSourceCreateWithURL(url as CFURL, opts),
          let propsCF = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) else {
        return nil
    }

    // 用 “字符串键” 访问（避免 kCGImageProperty* 常量）
    let props = propsCF as NSDictionary

    // A) 通用顶层：Depth（有些格式直接给总位深）
    if let depth = props["Depth"] as? NSNumber, depth.intValue > 0 {
        return depth.intValue
    }

    // B) TIFF/EXIF：{TIFF} -> BitsPerSample（可能是数组）× 通道数
    if let tiff = props["{TIFF}"] as? NSDictionary,
       let bpsAny = tiff["BitsPerSample"] {
        if let arr = bpsAny as? [NSNumber], !arr.isEmpty {
            // [8,8,8] -> 24
            return arr.reduce(0) { $0 + $1.intValue }
        }
        if let bps = (bpsAny as? NSNumber)?.intValue {
            let channels = channelsFromColorModel(props["ColorModel"] as? String)
            return channels > 0 ? bps * channels : bps
        }
    }

    // C) PNG：{PNG} -> BitDepth(每通道) + ColorType -> 推断通道数
    if let png = props["{PNG}"] as? NSDictionary,
       let bitDepth = png["BitDepth"] as? NSNumber {
        let colorType = (png["ColorType"] as? NSNumber)?.intValue ?? 2
        // 0:Gray(1), 2:RGB(3), 3:Indexed(1), 4:Gray+Alpha(2), 6:RGBA(4)
        let channels: Int = {
            switch colorType {
            case 0: return 1
            case 2: return 3
            case 3: return 1
            case 4: return 2
            case 6: return 4
            default: return 3
            }
        }()
        return colorType == 3 ? bitDepth.intValue : bitDepth.intValue * channels
    }

    // D) 兜底：解一张 CGImage 看 bitsPerPixel
    if let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) {
        let bpp = cg.bitsPerPixel
        return bpp > 0 ? bpp : nil
    }
    return nil
}

private func channelsFromColorModel(_ model: String?) -> Int {
    switch model {
    case "RGB":  return 3
    case "Gray": return 1
    case "CMYK": return 4
    case "Lab":  return 3
    default:     return 0
    }
}
