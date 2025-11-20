//
//  WindowHelpers.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import AppKit

// MARK: - WindowZoomHelper
final class WindowZoomHelper: NSObject, NSWindowDelegate {
    static let shared = WindowZoomHelper()
    var pendingStandardFrame: NSRect?

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
        if let f = pendingStandardFrame { return f }
        return defaultFrame
    }
}

// MARK: - Window Resize Functions
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
    var contentH = layoutH + layoutExtraH

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
    
    window.setFrame(targetFrame, display: true, animate: false)
}

func scaledContentSize(for base: CGSize, scale: CGFloat, window: NSWindow) -> CGSize {
    let vf = window.screen?.visibleFrame ?? (NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? .zero
    let maxW = max(vf.width, 200)
    let maxH = max(vf.height, 200)
    return CGSize(width: ceil(min(base.width * scale, maxW)), height: ceil(min(base.height * scale, maxH)))
}

