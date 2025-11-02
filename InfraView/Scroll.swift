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

// MARK: - CenteringScrollView (方案B：容器居中)

struct CenteringScrollView<Content: View>: NSViewRepresentable {
    let contentSize: CGSize                 // 缩放后的图像点尺寸（建议已 floor）
    let recenterMode: RecenterMode
    let recenterKey: AnyHashable
    @ViewBuilder var content: () -> Content

    @preconcurrency @MainActor
    final class Coordinator {
        var scrollView: NSScrollView!
        var container: NSView!              // ← 容器作为 documentView（固定引用）
        var hosting: NSHostingView<Content>!// ← 实际内容
        var lastKey: AnyHashable?
        
        nonisolated deinit {}
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.scrollerStyle = .legacy
        sv.autohidesScrollers = true
        sv.hasHorizontalScroller = true
        sv.hasVerticalScroller   = true
        sv.usesPredominantAxisScrolling = true

        // 默认 NSClipView
        let clip = NSClipView(frame: sv.contentView.frame)
        clip.drawsBackground = false
        sv.contentView = clip

        // 容器 + 内容
        let container = NSView(frame: .init(origin: .zero, size: contentSize))
        let host = NSHostingView(rootView: content())
        host.frame = .init(origin: .zero, size: contentSize)
        container.addSubview(host)

        sv.documentView = container

        context.coordinator.scrollView = sv
        context.coordinator.container  = container
        context.coordinator.hosting    = host
        context.coordinator.lastKey    = recenterKey

        // 初次：先布局→按轴居中→再按模式滚动一次
        DispatchQueue.main.async {
            sv.layoutSubtreeIfNeeded()
            layout(container: container, host: host, in: sv, contentSize: contentSize)
            recenterIfNeeded(sv: sv, mode: recenterMode)
        }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let container = context.coordinator.container,
              let host      = context.coordinator.hosting else { return }

        // 更新内容与尺寸
        host.rootView = content()
        host.frame.size = contentSize

        // 先让系统决定滚动条，再计算容器居中
        sv.layoutSubtreeIfNeeded()
        layout(container: container, host: host, in: sv, contentSize: contentSize)

        // 仅在 key 变化时执行“对齐一次”
        if context.coordinator.lastKey != recenterKey {
            context.coordinator.lastKey = recenterKey
            DispatchQueue.main.async { recenterIfNeeded(sv: sv, mode: recenterMode) }
        }
    }

    // MARK: - 布局：非滚动轴容器>=clip并把内容居中；滚动轴容器=内容并贴边
    private func layout(container: NSView, host: NSHostingView<Content>, in sv: NSScrollView, contentSize: CGSize) {
        let clip = sv.contentView.bounds.size
        let eps: CGFloat = 0.75

        let needH = contentSize.width  > clip.width  + eps
        let needV = contentSize.height > clip.height + eps

        let contW = needH ? contentSize.width  : max(contentSize.width,  clip.width)
        let contH = needV ? contentSize.height : max(contentSize.height, clip.height)
        container.frame.size = .init(width: floor(contW), height: floor(contH))

        let ox = needH ? 0 : floor((contW - contentSize.width)  / 2.0)
        let oy = needV ? 0 : floor((contH - contentSize.height) / 2.0)
        host.frame.origin = .init(x: max(0, ox), y: max(0, oy))
    }

    // MARK: - 一次性滚动对齐：按容器尺寸clamp到[0, container-clip]
    private func recenterIfNeeded(sv: NSScrollView, mode: RecenterMode) {
        guard let doc = sv.documentView else { return } // 这里的 doc 就是 container
        sv.layoutSubtreeIfNeeded()

        let clip = sv.contentView.bounds.size
        let docSize = doc.bounds.size

        @inline(__always) func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
        let maxX = max(0, docSize.width  - clip.width)
        let maxY = max(0, docSize.height - clip.height)

        let desired: NSPoint? = {
            switch mode {
            case .none:
                return nil
            case .topLeft:
                // 非 flipped：左上 = (0, docH - clipH)
                return NSPoint(x: 0, y: docSize.height - clip.height)
            case .imageCenter:
                return NSPoint(x: (docSize.width  - clip.width)  / 2,
                               y: (docSize.height - clip.height) / 2)
            case .visibleCenter:
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
            o.x = clamp(o.x, 0, maxX)
            o.y = clamp(o.y, 0, maxY)
            sv.contentView.scroll(to: o)
            sv.reflectScrolledClipView(sv.contentView)
        }
    }
}



/// 仅在 token 变化时，对“可滚动轴”滚动一次；不可滚轴不动，保持原生效果
struct ScrollAligner: NSViewRepresentable {
    let mode: RecenterMode
    let token: UUID   // 想对齐一次就换一个 UUID()

    final class Marker: NSView {}
    final class Coord {
        weak var sv: NSScrollView?
        var lastToken: UUID?
    }
    func makeCoordinator() -> Coord { Coord() }

    func makeNSView(context: Context) -> NSView {
        let v = Marker()
        DispatchQueue.main.async { attachIfNeeded(v, context) }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        attachIfNeeded(v, context)
        guard let sv = context.coordinator.sv else { return }
        if context.coordinator.lastToken != token {
            context.coordinator.lastToken = token
            // 等一拍，让 ScrollView 完成这轮布局与滚动条判定
            scheduleAlign(sv)
        }
    }

    // MARK: - Helpers

    private func attachIfNeeded(_ v: NSView, _ context: Context) {
        guard context.coordinator.sv == nil else { return }
        var p: NSView? = v
        while let cur = p {
            if let sv = cur as? NSScrollView {
                context.coordinator.sv = sv
                sv.usesPredominantAxisScrolling = true   // 更自然的滚轮手感
                // Align at the first time
                DispatchQueue.main.async { self.scheduleAlign(sv) }
                break
            }
            p = cur.superview
        }
    }

    private let settleMaxTries = 4
    private let settleEps: CGFloat = 1.0

    /// 最多四拍：等待 clip/doc/可滚状态稳定后再对齐
    private func scheduleAlign(_ sv: NSScrollView) {
        var tries = 0
        var lastClip = CGSize.zero
        var lastDoc  = CGSize.zero
        var lastCanH: Bool? = nil
        var lastCanV: Bool? = nil

        func step() {
            tries += 1
            sv.layoutSubtreeIfNeeded()

            let clip = sv.contentView.bounds.size
            let doc  = sv.documentView?.bounds.size ?? .zero

            let eps: CGFloat = settleEps
            let canH = doc.width  > clip.width  + eps
            let canV = doc.height > clip.height + eps

            let stable = (clip == lastClip && doc == lastDoc &&
                          canH == lastCanH && canV == lastCanV)

            if stable || tries >= settleMaxTries {
                alignOnce(sv)
            } else {
                lastClip = clip; lastDoc = doc
                lastCanH = canH;  lastCanV = canV
                DispatchQueue.main.async { step() }
            }
        }
        DispatchQueue.main.async { step() }
    }


    private func alignOnce(_ sv: NSScrollView) {
        guard let docView = sv.documentView else { return }
        sv.layoutSubtreeIfNeeded()

        let clip = sv.contentView.bounds.size
        let doc  = docView.bounds.size

        let eps: CGFloat = 0.5
        let canScrollH = doc.width  > clip.width  + eps
        let canScrollV = doc.height > clip.height + eps

        // 目标 origin（以容器/doc 为参照；AppKit 非 flipped）
        let desired: NSPoint? = {
            switch mode {
            case .none:
                return nil
            case .topLeft:
                // x=0，y=docH-clipH；不可滚轴保持现状
                return NSPoint(x: 0, y: doc.height - clip.height)
            case .imageCenter:
                return NSPoint(x: (doc.width  - clip.width ) / 2,
                               y: (doc.height - clip.height) / 2)
            case .visibleCenter:
                let vis = sv.contentView.bounds
                let centerInView = CGPoint(x: vis.midX, y: vis.midY)
                let centerInDoc  = sv.contentView.convert(centerInView, to: docView)
                return NSPoint(x: centerInDoc.x - vis.width / 2,
                               y: centerInDoc.y - vis.height / 2)
            case .cursor:
                guard let win = sv.window else { return nil }
                let mouseScreen = NSEvent.mouseLocation
                let mouseWin    = win.convertPoint(fromScreen: mouseScreen)
                let mouseScroll = sv.convert(mouseWin, from: nil)
                let mouseDoc    = sv.contentView.convert(mouseScroll, to: docView)
                return NSPoint(x: mouseDoc.x - clip.width  / 2,
                               y: mouseDoc.y - clip.height / 2)
            }
        }()
        guard var o = desired else { return }

        // clamp 到合法范围
        let maxX = max(0, doc.width  - clip.width)
        let maxY = max(0, doc.height - clip.height)
        o.x = min(max(o.x, 0), maxX)
        o.y = min(max(o.y, 0), maxY)

        // 仅修改“可滚动”的轴；不可滚轴不动 → 保留原生的居中/贴边
        var origin = sv.contentView.bounds.origin
        if canScrollH { origin.x = o.x }
        if canScrollV { origin.y = o.y }

        sv.contentView.scroll(to: origin)
        sv.reflectScrolledClipView(sv.contentView)
    }
}
