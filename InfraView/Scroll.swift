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

/// SwiftUI 和 AppKit 之间的桥接协议
/// SwiftUI 是声明式，macOS 底层 UI 还是 AppKit （基于 NSView）
/// 返回一个原生 AppKit 视图： NSView 对象 Marker
struct ScrollAligner: NSViewRepresentable {
    let mode: RecenterMode

    var onMarqueeFinished: ((NSRect) -> Void)? = nil   // 返回 document 坐标的选框

    // 透明交互层，覆盖在 NSScrollView 区域，捕捉鼠标事件
    final class Marker: NSView {
        weak var coord: Coord?
        var onMarqueeFinished: ((NSRect) -> Void)?

        // 选框绘制
        private var startDoc: NSPoint?
        private var marqueeLayer: CAShapeLayer?

        // 接收第一响应 & 首次点击，不影响使用就删了吧
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }


        // 首次进入窗口/父视图时再尝试 attach（确保首帧就挂到 clipView 顶层）
        var requestAttach: ((Marker) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow();
            requestAttach?(self)
            NSCursor.arrow.set()
            // color
            wantsLayer = true
            layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.5).cgColor
        }
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            requestAttach?(self)
            NSCursor.arrow.set()
            // color
            wantsLayer = true
            layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.5).cgColor
        }
        
        // 不拦截滚轮/触控板滚动，交回给 NSScrollView
        override func scrollWheel(with event: NSEvent) {
            nextResponder?.scrollWheel(with: event)
        }

        // 透明层也能吃事件
        override func hitTest(_ point: NSPoint) -> NSView? {
            return self.bounds.contains(point) ? self : nil
        }
        override func rightMouseDown(with event: NSEvent) {
            print("rightMouseDown")
            NSCursor.openHand.set()
        }
        override func rightMouseDragged(with event: NSEvent) {
            guard let sv = coord?.sv else { return }
            let dx = event.deltaX
            let dy = event.deltaY
            guard dx != 0 || dy != 0 else { return }

            let clip = sv.contentView  // 可视窗口 NSClipView
            var b = clip.bounds  // 可视区域的矩形
            print(b)
            b.origin.x -= dx
            b.origin.y -= dy

            let constrained = clip.constrainBoundsRect(b)
            clip.setBoundsOrigin(constrained.origin)
            // 让 NSScrollView 同步 UI，更新滚动条位置
            // sv.reflectScrolledClipView(clip)
            NSCursor.closedHand.set()
        }

        override func rightMouseUp(with event: NSEvent) {
            NSCursor.arrow.set()
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            NSCursor.arrow.set()
        }
        // MARK: - Marquee（左键）
        override func mouseDown(with event: NSEvent) {
            print("mouseDown")
            // ScrollView 和内容层 documentView
            guard let sv = coord?.sv,
                  let doc = sv.documentView else { return }
            // 只有第一响应者能继续收到 mouseDragged、mouseUp 等后续事件。
            window?.makeFirstResponder(self)
            // 点击坐标
            let win = event.locationInWindow
            print("win:", win)
            /*
            let inScroll = sv.convert(win, from: nil)
            print("inScroll:", inScroll)
            startDoc = sv.contentView.convert(inScroll, to: doc)
            print("startDoc:", startDoc)
            */
            startDoc = win
            ensureMarqueeLayer()
            let rect = NSRect(x: win.x, y: win.y, width: 100, height: 80)
            drawMarquee(rect, in: sv)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let sv = coord?.sv,
                  let doc = sv.documentView, let s = startDoc else { return }
            let win = event.locationInWindow
            /*
            let inScroll = sv.convert(win, from: nil)
            let cur = sv.contentView.convert(inScroll, to: doc)
             */
            let cur = win
            let rect = NSRect(x: min(s.x, cur.x), y: min(s.y, cur.y),
                              width: abs(cur.x - s.x), height: abs(cur.y - s.y))
            drawMarquee(rect, in: sv)
        }
        override func mouseUp(with event: NSEvent) {
            guard let sv = coord?.sv,
                  let doc = sv.documentView, let s = startDoc else { return }
            let win = event.locationInWindow
            let inScroll = sv.convert(win, from: nil)
            let cur = sv.contentView.convert(inScroll, to: doc)
            let rect = NSRect(x: min(s.x, cur.x), y: min(s.y, cur.y),
                              width: abs(cur.x - s.x), height: abs(cur.y - s.y))
            startDoc = nil
            clearMarquee()
            onMarqueeFinished?(rect)   // 回调：document 坐标
        }
  
        private func ensureMarqueeLayer() {
            if marqueeLayer == nil {
                let l = CAShapeLayer()
                l.fillColor = NSColor.clear.cgColor
                l.strokeColor = NSColor.controlAccentColor.cgColor
                l.lineDashPattern = [4, 3] as [NSNumber]
                l.lineWidth = 1
                l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
                self.wantsLayer = true
                self.layer?.addSublayer(l)
                marqueeLayer = l
            }
        }
        private func drawMarquee(_ rectDoc: NSRect, in sv: NSScrollView) {
            print("rectDoc:", rectDoc)
            guard let l = marqueeLayer,
                  let doc = sv.documentView else { return }
            // 把 doc 坐标矩形变换到 clipView（也就是 Marker）坐标来画
            let a = sv.contentView.convert(rectDoc.origin, from: doc)
            let b = sv.contentView.convert(NSPoint(x: rectDoc.maxX, y: rectDoc.maxY), from: doc)
            let vis = sv.documentVisibleRect
            let r = NSRect(x: min(a.x, b.x) + vis.minX, y: min(a.y, b.y),
                           width: abs(b.x - a.x), height: abs(b.y - a.y))
            
            print("r:", r)
            print("vis:", vis)
            l.frame = self.bounds
            l.path = CGPath(rect: r, transform: nil)
        }
        private func clearMarquee() {
            marqueeLayer?.path = nil
        }
    }
    final class Coord {
        weak var sv: NSScrollView?
    }
    func makeCoordinator() -> Coord { Coord() }

    func makeNSView(context: Context) -> NSView {
        print("makeNSView")
        let v = Marker()
        v.coord = context.coordinator
        v.onMarqueeFinished = onMarqueeFinished

        v.requestAttach = { m in self.attachIfNeeded(m, context) }
        //self.attachIfNeeded(v, context)

        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        print("updateNSView")
        /*
        if let m = v as? Marker {
            m.coord = context.coordinator
            m.onMarqueeFinished = onMarqueeFinished
            m.requestAttach = { m in
                self.attachIfNeeded(m, context)
            }
        }
        attachIfNeeded(v, context)
        */
        //guard let sv = context.coordinator.sv else { return }
        //DispatchQueue.main.async { self.alignOnce(sv) }
    }

    // MARK: - Helpers

    private func attachIfNeeded(_ v: NSView, _ context: Context) {
        print("attachIfNeeded")
        guard context.coordinator.sv == nil else { return }
        var p: NSView? = v
        while let cur = p {
            if let sv = cur as? NSScrollView {
                context.coordinator.sv = sv
                // 把 Marker 放到 clipView 顶层覆盖整个可视区
                if let marker = v as? Marker {
                    let clip = sv.contentView
                    var f = clip.bounds
                    print("f:", f)
                    f.origin = .zero
                    // 把 Marker 挂在 AppKit 的 clipView 上，
                    // 并且放在 documentView 之上
                    
                    clip.addSubview(marker, positioned: .above, relativeTo: sv.contentView)
                }
                // Align at the first time
                DispatchQueue.main.async { self.alignOnce(sv) }
                break
            }
            p = cur.superview
        }
    }

    private func alignOnce(_ sv: NSScrollView) {
        print("alignOnce")
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
