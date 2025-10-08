// InfraCore.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

// MARK: - Model

enum FitMode: String, CaseIterable {
    case fitWindowToImage = "Fit window to image"
    case fitImageToWindow = "Fit image to window"
    case fitOnlyBigToWindow = "Fit only big images to window"
    case fitOnlyBigToDesktop = "Fit only big images to desktop"
    case doNotFit = "Do not fit anything"
}

enum BookmarkStore {
    private static let defaultsKey = "ScopedBookmarks"

    static func save(url: URL) {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            var dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
            let key = url.standardizedFileURL.path
            dict[key] = data
            UserDefaults.standard.set(dict, forKey: defaultsKey)
        } catch {
            print("Save bookmark failed:", error)
        }
    }

    /// 尝试命中精确目录；否则做“最长祖先目录”的匹配
    static func resolve(matching parent: URL) -> URL? {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] else {
            return nil
        }
        let parentPath = parent.standardizedFileURL.path

        // 1) 精确命中
        if let exact = dict[parentPath] {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: exact,
                                options: [.withSecurityScope, .withoutUI],
                                relativeTo: nil,
                                bookmarkDataIsStale: &stale),
               !stale {
                return u
            }
        }

        // 2) 祖先匹配（优先更长的祖先路径）
        let sorted = dict.keys.sorted { $0.count > $1.count }
        for k in sorted {
            if parentPath == k || parentPath.hasPrefix(k + "/") {
                if let data = dict[k] {
                    var stale = false
                    if let u = try? URL(resolvingBookmarkData: data,
                                        options: [.withSecurityScope, .withoutUI],
                                        relativeTo: nil,
                                        bookmarkDataIsStale: &stale),
                       !stale {
                        return u
                    }
                }
            }
        }
        return nil
    }
}







// Unknown functions
// MARK: - ImageRepository（把解码独立）
protocol ImageRepository {
    func load(at url: URL) throws -> (image: NSImage, pixelSize: CGSize)
}

final class ImageRepositoryImpl: ImageRepository {
    func load(at url: URL) throws -> (image: NSImage, pixelSize: CGSize) {
        // 直接使用你现有 decodeCGImageApplyingOrientation/loadCGForURL 的逻辑拼装
        let (cgOpt, px, err) = loadCGForURL(url)      // 从下方 Helpers 复用
        guard let cg = cgOpt else { throw NSError(domain: "InfraView", code: 2, userInfo: [NSLocalizedDescriptionKey: err ?? "Unsupported"]) }
        let scale = displayScaleFactor()
        let pt = NSSize(width: px.width/scale, height: px.height/scale)
        return (NSImage(cgImage: cg, size: pt), px)
    }
}

// MARK: - 轻量 LRU 缓存 + 预加载
final class ImageCache {
    private var dict: [URL:NSImage] = [:]
    private var order: [URL] = []
    private let cap: Int
    init(capacity: Int = 8) { self.cap = capacity }
    func get(_ u: URL) -> NSImage? { dict[u] }
    func set(_ u: URL, _ img: NSImage) {
        dict[u] = img; order.removeAll{ $0==u }; order.append(u)
        while order.count > cap { dict.removeValue(forKey: order.removeFirst()) }
    }
    func trim(keeping set: Set<URL>) {
        order.removeAll{ !set.contains($0) }
        dict = dict.filter{ set.contains($0.key) }
    }
}

final class ImagePreloader {
    private let repo: ImageRepository, cache: ImageCache
    init(repo: ImageRepository, cache: ImageCache) { self.repo = repo; self.cache = cache }
    func preload(adjacentOf idx: Int, in urls: [URL]) {
        guard !urls.isEmpty else { return }
        for i in [ (idx-1+urls.count)%urls.count, (idx+1)%urls.count ] {
            let u = urls[i]
            if cache.get(u) == nil {
                DispatchQueue.global(qos: .background).async {
                    if let (img, _) = try? self.repo.load(at: u) {
                        DispatchQueue.main.async { self.cache.set(u, img) }
                    }
                }
            }
        }
    }
}

// MARK: - WindowSizer（把窗口/滚动条/visibleFrame计算集中）
protocol WindowSizer {
    func fittedContentSize(for image: NSImage, in window: NSWindow) -> CGSize
    func accurateFitScale(for image: NSImage, in window: NSWindow) -> CGFloat
    func isBigOnDesktop(_ image: NSImage, window: NSWindow) -> Bool
    func resizeWindow(toContent size: CGSize, mode: FitMode)
}

final class WindowSizerImpl: WindowSizer {
    func fittedContentSize(for image: NSImage, in window: NSWindow) -> CGSize { /* 用你现有 fittedContentSizeAccurate */
        guard let win = currentWindow() else { return naturalPointSize(image) }

        let base = naturalPointSize(image)
        // 最大 contentLayout 尺寸（无余量）
        var avail = maxContentLayoutSizeInVisibleFrame(win)

        // 估算 legacy 滚动条厚度
        let (vBar, hBar) = legacyScrollbarThickness()

        // 两轮迭代：先假设无条，再根据是否超出决定扣条宽，再重算
        for _ in 0..<2 {
            let scale = min(avail.width / max(base.width, 1),
                            avail.height / max(base.height, 1))
            let w = floor(base.width * scale)    // 用 floor，避免 1px 溢出导致出条
            let h = floor(base.height * scale)

            // 判断是否仍会出条（> avail），如果会，给出“扣条后的可用区”再来一轮
            let needV = h > avail.height
            let needH = w > avail.width
            var nextAvail = avail
            if needV { nextAvail.width  = max(0, nextAvail.width  - vBar) }
            if needH { nextAvail.height = max(0, nextAvail.height - hBar) }

            if nextAvail == avail {
                // 收敛
                return CGSize(width: w, height: h)
            }
            avail = nextAvail
        }

        // 兜底（一般到不了）
        let scale = min(avail.width / max(base.width, 1),
                        avail.height / max(base.height, 1))
        return CGSize(width: floor(base.width * scale),
                      height: floor(base.height * scale))

    }
    func accurateFitScale(for image: NSImage, in window: NSWindow) -> CGFloat { /* 用你现有 accurateFitScale */
        guard let win = currentWindow() else { return 1 }
        let base = naturalPointSize(image)
        var avail = maxContentLayoutSizeInVisibleFrame(win)
        let (vBar, hBar) = legacyScrollbarThickness()
        for _ in 0..<2 {
            let s = min(avail.width / max(base.width, 1),
                        avail.height / max(base.height, 1))
            let w = floor(base.width * s), h = floor(base.height * s)
            let needV = h > avail.height
            let needH = w > avail.width
            var next = avail
            if needV { next.width  = max(0, next.width  - vBar) }
            if needH { next.height = max(0, next.height - hBar) }
            if next == avail { return s }
            avail = next
        }
        return min(avail.width / max(base.width, 1),
                   avail.height / max(base.height, 1))
    }
    func isBigOnDesktop(_ img: NSImage, window: NSWindow) -> Bool { /* 用 isBigOnThisDesktop + maxContentLayoutSizeInVisibleFrame */
        guard let win = currentWindow() else { return false }
        let natural = naturalPointSize(img)
        let maxLayout = maxContentLayoutSizeInVisibleFrame(win)
        return natural.width > maxLayout.width || natural.height > maxLayout.height
    }
    func resizeWindow(toContent size: CGSize, mode: FitMode) { /* 用 resizeWindowToContentSize(scrollbarAware: mode != .fitOnlyBigToDesktop) */
        let aware = (mode != .fitOnlyBigToDesktop)
        resizeWindowToContentSize(size, scrollbarAware: aware)
    }
    // 私有：搬 maxContentLayoutSizeInVisibleFrame / legacyScrollbarThickness 等 Helpers
    private func currentWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
    }
    private func maxContentLayoutSizeInVisibleFrame(_ window: NSWindow) -> CGSize {
        // 1) 屏幕的可用矩形（已扣除菜单栏/Dock）
        let vf = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // 2) 先求“contentRect 与 frameRect 的装饰差”
        //    用一个 100x100 的 dummy contentRect 反推出 frameRect，然后取差值
        let dummyContent = NSRect(x: 0, y: 0, width: 100, height: 100)
        let dummyFrame   = window.frameRect(forContentRect: dummyContent)
        let decoW = dummyFrame.width  - dummyContent.width
        let decoH = dummyFrame.height - dummyContent.height

        // 3) 当前窗口里 contentRect 与 contentLayoutRect 的差（工具栏等“吃掉”的区域）
        let currentFrame        = window.frame
        let currentContentRect  = window.contentRect(forFrameRect: currentFrame)
        let currentLayoutRect   = window.contentLayoutRect
        let layoutExtraW = max(0, currentContentRect.width  - currentLayoutRect.width)
        let layoutExtraH = max(0, currentContentRect.height - currentLayoutRect.height)

        // 4) 可容纳的最大 contentRect 尺寸 = visibleFrame 尺寸 - 窗口装饰
        let maxContentRectW = max(vf.width  - decoW, 0)
        let maxContentRectH = max(vf.height - decoH, 0)

        // 5) 再扣掉 contentRect → contentLayoutRect 的差，得到“最大 contentLayoutRect 尺寸”
        let maxLayoutW = max(maxContentRectW - layoutExtraW, 0)
        let maxLayoutH = max(maxContentRectH - layoutExtraH, 0)

        return CGSize(width: floor(maxLayoutW), height: floor(maxLayoutH))
    }
}















// MARK: - Helpers
func displayScaleFactor() -> CGFloat {
    if let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
       let s = w.screen { return s.backingScaleFactor }
    return NSScreen.main?.backingScaleFactor ?? 2.0
}

func pixelSize(_ img: NSImage) -> CGSize {
    var maxW = 0, maxH = 0
    for rep in img.representations where rep.pixelsWide > 0 && rep.pixelsHigh > 0 { maxW = max(maxW, rep.pixelsWide); maxH = max(maxH, rep.pixelsHigh) }
    if maxW == 0 || maxH == 0, let tiff = img.tiffRepresentation, let b = NSBitmapImageRep(data: tiff) {
        maxW = max(maxW, b.pixelsWide); maxH = max(maxH, b.pixelsHigh)
    }
    if maxW == 0 || maxH == 0 {
        let sf = displayScaleFactor(); let w = Int(img.size.width * sf), h = Int(img.size.height * sf)
        if w > 0 && h > 0 { maxW = w; maxH = h }
    }
    return CGSize(width: CGFloat(maxW), height: CGFloat(maxH))
}

func naturalPointSize(_ img: NSImage) -> CGSize {
    let px = pixelSize(img); let sf = displayScaleFactor(); return CGSize(width: px.width / sf, height: px.height / sf)
}

func legacyScrollbarThickness() -> (vertical: CGFloat, horizontal: CGFloat) {
    if NSScroller.preferredScrollerStyle == .overlay { return (0, 0) }
    let t = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy); return (vertical: t, horizontal: t)
}

func scaledContentSize(for image: NSImage, scale: CGFloat) -> CGSize {
    let base = naturalPointSize(image)
    let vf = (NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
    let maxW = max(vf.width, 200)
    let maxH = max(vf.height, 200)
    return CGSize(width: ceil(min(base.width * scale, maxW)), height: ceil(min(base.height * scale, maxH)))
}

func resizeWindowToContentSize(_ desiredContentSize: CGSize, scrollbarAware: Bool = true) {
    guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }

    // ✅ 关键补丁：先确保窗口不是 zoomed / fullScreen
    if window.styleMask.contains(.fullScreen) { return }      // 全屏下不处理

    let minW: CGFloat = 360, minH: CGFloat = 280
    var layoutW = max(ceil(desiredContentSize.width),  minW)
    var layoutH = max(ceil(desiredContentSize.height), minH)

    let currentFrame = window.frame
    let currentContentRect = window.contentRect(forFrameRect: currentFrame)
    let currentLayoutRect = window.contentLayoutRect
    let layoutExtraW = max(0, currentContentRect.width  - currentLayoutRect.width)
    let layoutExtraH = max(0, currentContentRect.height - currentLayoutRect.height)

    var contentW = layoutW + layoutExtraW
    var contentH = layoutH + layoutExtraH + (scrollbarAware ? 1 : 0)

    let (vBar, hBar) = legacyScrollbarThickness()
    let vf = (window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero

    let testContentRect = NSRect(x: 0, y: 0, width: 100, height: 100)
    let testFrame = window.frameRect(forContentRect: testContentRect)
    let decoW = testFrame.width  - testContentRect.width
    let decoH = testFrame.height - testContentRect.height
    var availW = max(vf.width  - decoW, minW)
    var availH = max(vf.height - decoH, minH)
    
    if scrollbarAware {
        var needV = contentH > availH
        var needH = contentW > availW
        for _ in 0..<2 {
            var nextAvailW = availW
            var nextAvailH = availH
            if needV { nextAvailW -= vBar }
            if needH { nextAvailH -= hBar }
            let nextNeedV = contentH > nextAvailH
            let nextNeedH = contentW > nextAvailW
            if nextNeedV == needV && nextNeedH == needH { break }
            needV = nextNeedV; needH = nextNeedH
            availW = nextAvailW; availH = nextAvailH
        }
        if needV { contentW += vBar }
        if needH { contentH += hBar }
    } else {
        contentW = min(contentW, availW)
        contentH = min(contentH, availH)
    }
    var targetFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH))
    let currentTop = window.frame.maxY
    targetFrame.origin.x = window.frame.origin.x
    targetFrame.origin.y = currentTop - targetFrame.height

    if let screen = window.screen {
        let vf2 = screen.visibleFrame
        if targetFrame.width  > vf2.width  { targetFrame.size.width  = vf2.width }
        if targetFrame.height > vf2.height { targetFrame.size.height = vf2.height }
        targetFrame.origin.x = min(max(vf2.minX, targetFrame.origin.x), vf2.maxX - targetFrame.width)
        targetFrame.origin.y = max(vf2.minY, currentTop - targetFrame.height)
    }
    if window.isZoomed {
        // window.zoom(nil)
        // 在 zoomed 状态下，用 delegate 指定“标准帧”= targetFrame，然后执行一次无动画 zoom
        let helper = WindowZoomHelper.shared
        let oldDelegate = window.delegate
        window.delegate = helper
        helper.pendingStandardFrame = targetFrame

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0  // 无动画切换，避免“半屏回弹”的视觉跳变
            window.zoom(nil)  // 退出 zoomed，直接采用我们提供的标准帧
        }

        helper.pendingStandardFrame = nil
        window.delegate = oldDelegate
    }                   // 退出“标准缩放”状态
    else {
        window.setFrame(targetFrame, display: true, animate: false)
    }
}

func decodeCGImageApplyingOrientation(_ url: URL) -> (CGImage?, CGSize, String?) {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return (nil, .zero, "Unable to create image source.")
    }

    // 先取像素尺寸（不用创建整图，避免额外解码）
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as NSDictionary?
    let pxW = (props?[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
    let pxH = (props?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
    let maxDim = Int(max(pxW, pxH))

    // 用“缩略图”API但把目标尺寸设为原始最大边 + transform=true
    // 好处：ImageIO 会自动应用 EXIF 方向，不需要我们手写矩阵
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDim,
        kCGImageSourceCreateThumbnailWithTransform: true, // ✅ 应用 EXIF 方向
        kCGImageSourceShouldCache: false                  // 不提前缓存像素
    ]

    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
        return (nil, .zero, "Unsupported image format.")
    }
    // 注意：经方向修正后，像素宽高可能互换（例如 90° 旋转）
    let outSize = CGSize(width: cg.width, height: cg.height)
    return (cg, outSize, nil)
}

func loadCGForURL(_ url: URL) -> (CGImage?, CGSize, String?) {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }

    guard FileManager.default.fileExists(atPath: url.path) else { return (nil, .zero, "File does not exist.") }
    guard FileManager.default.isReadableFile(atPath: url.path) else { return (nil, .zero, "File cannot be read.") }

    let (cgOpt, pixelSize, err) = decodeCGImageApplyingOrientation(url)
    return (cgOpt, pixelSize, err)
}

@inline(__always)
func clamp<T: Comparable>(_ x: T, _ r: ClosedRange<T>) -> T { min(max(x, r.lowerBound), r.upperBound) }
