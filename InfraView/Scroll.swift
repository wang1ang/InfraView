//
//  Scroll.swift
//  InfraView
//
//  Created by 王洋 on 10/10/2025.
//

import SwiftUI
import AppKit

enum RecenterMode {
    case none
    case topLeft
    case visibleCenter
    case imageCenter
    case cursor
}

/// 一个“会在无滚动时居中内容”的 ClipView：
/// 若文档尺寸小于可见尺寸，则把该轴的 bounds.origin 放到 (doc - clip)/2（可能是负值），从而实现视觉居中；
/// 若文档尺寸大于可见尺寸，则保持正常滚动行为。
final class CenteringClipView: NSClipView {
    override var isFlipped: Bool { false }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = self.documentView else { return rect }

        let clip = self.bounds.size
        let docSize = doc.bounds.size

        // 像素对齐：按当前窗口/屏幕 scale 将 origin 四舍五入到像素网格
        let scale = self.window?.backingScaleFactor
            ?? self.window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0
        let step: CGFloat = 1.0 / scale
        @inline(__always) func snap(_ v: CGFloat) -> CGFloat {
            (v / step).rounded(.toNearestOrAwayFromZero) * step
        }

        if docSize.width <= clip.width {
            // 由 floor 改为 snap，避免负数向 -∞ 偏移导致“偏右”
            rect.origin.x = snap( (docSize.width - clip.width) / 2.0 )
        }
        if docSize.height <= clip.height {
            // 同理，snap 避免“偏上”
            rect.origin.y = snap( (docSize.height - clip.height) / 2.0 )
        }
        return rect
    }
}


struct CenteringScrollView<Content: View>: NSViewRepresentable {
    let contentSize: CGSize
    let recenterMode: RecenterMode
    let recenterKey: AnyHashable
    @ViewBuilder var content: () -> Content

    final class Coordinator {
        var scrollView: NSScrollView!
        var hosting: NSHostingView<Content>!
        var lastKey: AnyHashable?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.scrollerStyle = .legacy
        sv.autohidesScrollers = true
        sv.hasHorizontalScroller = true
        sv.hasVerticalScroller = true

        // ✅ 用默认的 NSClipView（不自动居中）
        let clip = NSClipView(frame: sv.contentView.frame)
        clip.drawsBackground = false
        sv.contentView = clip

        let host = NSHostingView(rootView: content())
        host.frame = .init(origin: .zero, size: contentSize)
        sv.documentView = host

        context.coordinator.scrollView = sv
        context.coordinator.hosting = host
        context.coordinator.lastKey = recenterKey

        DispatchQueue.main.async {
            sv.layoutSubtreeIfNeeded()
            recenterIfNeeded(sv: sv, mode: recenterMode)
        }
        return sv
    }


    func updateNSView(_ sv: NSScrollView, context: Context) {
        // 更新内容和尺寸
        if let host = context.coordinator.hosting {
            host.rootView = content()
            host.frame.size = contentSize
        }

        // 让系统先决定是否需要滚动条（会影响 clip 的有效尺寸）
        sv.layoutSubtreeIfNeeded()

        // 根据请求做对齐（只在 key 变化时触发一次）
        if context.coordinator.lastKey != recenterKey {
            context.coordinator.lastKey = recenterKey
            DispatchQueue.main.async { recenterIfNeeded(sv: sv, mode: recenterMode) }
        }
    }

    // 只在需要时滚动到指定锚点；当某轴 doc <= clip 时，不移动该轴（让 ClipView 保持居中）
    private func recenterIfNeeded(sv: NSScrollView, mode: RecenterMode) {
        guard let doc = sv.documentView else { return }
        // 确保尺寸是最新的
        sv.layoutSubtreeIfNeeded()

        let clip = sv.contentView.bounds.size
        let docSize = doc.bounds.size

        @inline(__always) func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            min(max(v, lo), hi)
        }

        // 经典可滚动范围：非 flipped 坐标，原点在左下，Y 向上
        let maxX = max(0, docSize.width  - clip.width)
        let maxY = max(0, docSize.height - clip.height)

        // 先算“期望的”原点，再统一 clamp 到合法范围
        let desired: NSPoint? = {
            switch mode {
            case .none:
                return nil

            case .topLeft:
                // 左上：x=0，y=docH-clipH（若 doc<clip，会在 clamp 后落到 0）
                return NSPoint(x: 0, y: docSize.height - clip.height)

            case .imageCenter:
                // 图片中心
                return NSPoint(x: (docSize.width  - clip.width)  / 2,
                               y: (docSize.height - clip.height) / 2)

            case .visibleCenter:
                // 以缩放前的可见中心为锚点
                let vis = sv.contentView.bounds
                let cInView = CGPoint(x: vis.midX, y: vis.midY)
                let cInDoc  = sv.contentView.convert(cInView, to: doc)
                return NSPoint(x: cInDoc.x - vis.width  / 2,
                               y: cInDoc.y - vis.height / 2)

            case .cursor:
                guard let win = sv.window else { return nil }
                let mouseScreen = NSEvent.mouseLocation
                let mouseWin    = win.convertPoint(fromScreen: mouseScreen)
                let mouseScroll = sv.convert(mouseWin, from: nil)
                let mouseDoc    = sv.contentView.convert(mouseScroll, to: doc)
                return NSPoint(x: mouseDoc.x - clip.width  / 2,
                               y: mouseDoc.y - clip.height / 2)
            }
        }()

        if var o = desired {
            // 统一 clamp 到 [0, max]
            o.x = clamp(o.x, 0, maxX)
            o.y = clamp(o.y, 0, maxY)

            // 用 scroll(to:) 更稳妥
            sv.contentView.scroll(to: o)
            sv.reflectScrolledClipView(sv.contentView)
        }
    }


}
