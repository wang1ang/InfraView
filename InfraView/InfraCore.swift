// InfraCore.swift
import SwiftUI
import AppKit
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

// MARK: - WindowSizer（把窗口/滚动条/visibleFrame计算集中）
protocol WindowSizer {
    func fittedContentSize(for image: NSImage, in window: NSWindow) -> CGSize
    func desktopFitScale(for image: NSImage, in window: NSWindow) -> CGFloat
    func isBigOnDesktop(_ image: NSImage, window: NSWindow) -> Bool
    func resizeWindow(toContent size: CGSize, mode: FitMode)
}

@MainActor
final class WindowSizerImpl: WindowSizer {

    func fittedContentSize(for image: NSImage, in window: NSWindow) -> CGSize { // 按当前窗口计算可视面积

        let base = naturalPointSize(image)
        // 最大 contentLayout 尺寸（无余量）
        var avail = maxAvailableContentSize(window)

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
    func desktopFitScale(for image: NSImage, in window: NSWindow) -> CGFloat {
        // 按屏幕大小计算可视面积
        let base = naturalPointSize(image)
        let avail = maxAvailableContentSize(window)
        /*
        let (vBar, hBar) = legacyScrollbarThickness()
        for _ in 0..<2 {
            // 缩放到屏幕的大小
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
        */
        return min(avail.width / max(base.width, 1),
                   avail.height / max(base.height, 1))
    }
    func isBigOnDesktop(_ img: NSImage, window: NSWindow) -> Bool { /* 用 isBigOnThisDesktop + maxAvailableContentSize */
        let natural = naturalPointSize(img)
        let maxLayout = maxAvailableContentSize(window)
        return natural.width > maxLayout.width || natural.height > maxLayout.height
    }
    func resizeWindow(toContent size: CGSize, mode: FitMode) {
        resizeWindowToContentSize(size, scrollbarAware: true)
        // 全都传 true 没有发现问题
        //let aware = (mode != .fitOnlyBigToDesktop)
        //resizeWindowToContentSize(size, scrollbarAware: aware)
    }
    // 私有：搬 maxAvailableContentSize / legacyScrollbarThickness 等 Helpers
    private func currentWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
    }
    private func maxAvailableContentSize(_ window: NSWindow) -> CGSize {
        // 1) 屏幕的可用矩形（已扣除菜单栏/Dock）
        let vf = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // 2) 先求“contentRect 与 frameRect 的装饰差”
        //    用一个 100x100 的 dummy contentRect 反推出 frameRect，然后取差值
        //    在我的代码里没有标题栏和边框，所以里都是0
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

        let bottomStatusBar = StatusBarStore.shared.height
        // 4) 可容纳的最大 contentRect 尺寸 = visibleFrame 尺寸 - 窗口装饰
        let maxLayoutW = max(vf.width  - decoW - layoutExtraW, 0)
        let maxLayoutH = max(vf.height - decoH - layoutExtraH - bottomStatusBar, 0)

        return CGSize(width: floor(maxLayoutW), height: floor(maxLayoutH))
    }
}















// MARK: - Helpers
final class WindowZoomHelper: NSObject, NSWindowDelegate {
    static let shared = WindowZoomHelper()
    var pendingStandardFrame: NSRect?

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
        if let f = pendingStandardFrame { return f }
        return defaultFrame
    }
}

@MainActor
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

@MainActor
func resizeWindowToContentSize(_ desiredContentSize: CGSize, scrollbarAware: Bool = true) {
    print ("resizeWindowToContentSize")
    // 获取目标窗口
    guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
    // 先确保窗口不是 zoomed / fullScreen
    if window.styleMask.contains(.fullScreen) { return }      // 全屏下不处理
    
    let bottomBarHeight = StatusBarStore.shared.height

    // 设置最小尺寸
    let minW: CGFloat = 360, minH: CGFloat = 280
    var layoutW = max(ceil(desiredContentSize.width),  minW)
    var layoutH = max(ceil(desiredContentSize.height + bottomBarHeight), minH)

    // 获取当前窗口的矩形信息
    let currentFrame = window.frame // 整个窗口
    let currentContentRect = window.contentRect(forFrameRect: currentFrame) // 去掉标题栏 （不包含标题栏）
    let currentLayoutRect = window.contentLayoutRect // 去掉工具栏

    // 标题栏大小
    let layoutExtraW = max(0, currentContentRect.width  - currentLayoutRect.width)
    let layoutExtraH = max(0, currentContentRect.height - currentLayoutRect.height)
    
    // 初步计算内容区大小
    var contentW = layoutW + layoutExtraW
    var contentH = layoutH + layoutExtraH //+ (scrollbarAware ? 1 : 0)

    // 🧭 获取滚动条厚度和屏幕可见区域
    let (vBar, hBar) = legacyScrollbarThickness()
    let vf = (window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero

    // 🧱 测试装饰尺寸（标题栏、边框）
    let testContentRect = NSRect(x: 0, y: 0, width: 100, height: 100)
    let testFrame = window.frameRect(forContentRect: testContentRect)
    let decoW = testFrame.width  - testContentRect.width
    let decoH = testFrame.height - testContentRect.height
    var availW = max(vf.width  - decoW, minW)
    var availH = max(vf.height - decoH, minH)
    
    // 🧮 如果要考虑滚动条，则自洽计算可用空间
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
    
    // 🧭 计算最终目标外框（保持上边缘不动）
    var targetFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH))
    let currentTop = window.frame.maxY
    targetFrame.origin.x = window.frame.origin.x
    targetFrame.origin.y = currentTop - targetFrame.height

    // 🖥️ 限制窗口在屏幕可见范围内
    if let screen = window.screen {
        let vf2 = screen.visibleFrame
        if targetFrame.width  > vf2.width  { targetFrame.size.width  = vf2.width }
        if targetFrame.height > vf2.height { targetFrame.size.height = vf2.height }
        targetFrame.origin.x = min(max(vf2.minX, targetFrame.origin.x), vf2.maxX - targetFrame.width)
        targetFrame.origin.y = max(vf2.minY, currentTop - targetFrame.height)
    }
    // 删掉下面的解决zoom放大以后窗口大小来回跳。
    // ⚙️ 处理 zoomed（标准缩放）状态
    /*
    if window.isZoomed {
        // window.zoom(nil)
        // 在 zoomed 状态下，用 delegate 指定“标准帧”= targetFrame，然后执行一次无动画 zoom
        let helper = WindowZoomHelper.shared
        let oldDelegate = window.delegate
        window.delegate = helper
        print("pendingStandardFrame: \(targetFrame)")
        helper.pendingStandardFrame = targetFrame

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0  // 无动画切换，避免“半屏回弹”的视觉跳变
            window.zoom(nil)  // 退出 zoomed，直接采用我们提供的标准帧
        }

        helper.pendingStandardFrame = nil
        window.delegate = oldDelegate
    }                   // 退出“标准缩放”状态
    // 🚪 非 zoomed 状态，直接设定新 frame
    else {
        window.setFrame(targetFrame, display: true, animate: false)
    }
    */
    window.setFrame(targetFrame, display: true, animate: false)
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
