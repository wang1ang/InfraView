//
//  WindowSizer.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import AppKit

// MARK: - WindowSizer（把窗口/滚动条/visibleFrame计算集中）
protocol WindowSizer {
    func fittedContentSize(for image: CGSize, in window: NSWindow) -> CGSize
    func desktopFitScale(for image: CGSize, in window: NSWindow) -> CGFloat
    func isBigOnDesktop(_ natural: CGSize, window: NSWindow) -> Bool
    func resizeWindow(toContent size: CGSize, mode: FitMode)
}

@MainActor
final class WindowSizerImpl: WindowSizer {

    func fittedContentSize(for base: CGSize, in window: NSWindow) -> CGSize { // 按当前窗口计算可视面积

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

            // 判断是否仍会出条（> avail），如果会，给出"扣条后的可用区"再来一轮
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
    func desktopFitScale(for base: CGSize, in window: NSWindow) -> CGFloat {
        // 按屏幕大小计算可视面积
        let avail = maxAvailableContentSize(window)
        return min(avail.width / max(base.width, 1),
                   avail.height / max(base.height, 1))
    }
    func isBigOnDesktop(_ natural: CGSize, window: NSWindow) -> Bool { /* 用 isBigOnThisDesktop + maxAvailableContentSize */
        let maxLayout = maxAvailableContentSize(window)
        return natural.width > maxLayout.width || natural.height > maxLayout.height
    }
    func resizeWindow(toContent size: CGSize, mode: FitMode) {
        resizeWindowToContentSize(size, scrollbarAware: true)
    }
    
    public func maxAvailableContentSize(_ window: NSWindow) -> CGSize {
        // 1) 屏幕的可用矩形（已扣除菜单栏/Dock）
        let vf = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // 2) 先求"contentRect 与 frameRect 的装饰差"
        //    用一个 100x100 的 dummy contentRect 反推出 frameRect，然后取差值
        //    在我的代码里没有标题栏和边框，所以里都是0
        let dummyContent = NSRect(x: 0, y: 0, width: 100, height: 100)
        let dummyFrame   = window.frameRect(forContentRect: dummyContent)
        let decoW = dummyFrame.width  - dummyContent.width
        let decoH = dummyFrame.height - dummyContent.height

        // 3) 当前窗口里 contentRect 与 contentLayoutRect 的差（工具栏等"吃掉"的区域）
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

