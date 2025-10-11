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


/// 在原生 ScrollView 内部悄悄拿到 NSScrollView，并在 token 变更时做一次性滚动定位
struct ScrollTuner: NSViewRepresentable {
    let mode: RecenterMode
    let token: UUID           // 每次要对齐→换一个 token
    let expectedDocSize: CGSize   // 你的“内容点尺寸”（缩放后），用于判稳

    final class Holder: NSView {}
    final class Coord {
        weak var sv: NSScrollView?
        var lastToken: UUID?
        var pending = false
    }
    func makeCoordinator() -> Coord { Coord() }

    func makeNSView(context: Context) -> NSView {
        let v = Holder()
        DispatchQueue.main.async { attachIfNeeded(v, context) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        attachIfNeeded(v, context)
        guard let sv = context.coordinator.sv else { return }
        if context.coordinator.lastToken != token {
            context.coordinator.lastToken = token
            scheduleOnce(sv: sv, context: context)
        }
    }

    private func attachIfNeeded(_ v: NSView, _ context: Context) {
        guard context.coordinator.sv == nil else { return }
        var p: NSView? = v
        while let cur = p {
            if let sv = cur as? NSScrollView {
                context.coordinator.sv = sv
                break
            }
            p = cur.superview
        }
    }

    /// 最多等 3 个 runloop tick：直到 clip/doc 稳定且 doc≈expected，再滚动
    private func scheduleOnce(sv: NSScrollView, context: Context) {
        guard context.coordinator.pending == false else { return }
        context.coordinator.pending = true
        var tries = 0
        var lastClip = CGSize.zero
        var lastDoc  = CGSize.zero

        func step() {
            tries += 1
            sv.layoutSubtreeIfNeeded()
            let clip = sv.contentView.bounds.size
            let doc  = sv.documentView?.bounds.size ?? .zero

            let docStable = hypot(doc.width - expectedDocSize.width,
                                  doc.height - expectedDocSize.height) <= 0.5

            if ((clip == lastClip && doc == lastDoc) && docStable) || tries >= 3 {
                context.coordinator.pending = false
                recenterNow(sv: sv, clip: clip, doc: doc)
            } else {
                lastClip = clip; lastDoc = doc
                DispatchQueue.main.async { step() }
            }
        }
        DispatchQueue.main.async { step() }
    }

    private func recenterNow(sv: NSScrollView, clip: CGSize, doc: CGSize) {
        guard let docView = sv.documentView else { return }

        @inline(__always) func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
        let maxX = max(0, doc.width  - clip.width)
        let maxY = max(0, doc.height - clip.height)

        let desired: NSPoint? = {
            switch mode {
            case .none:        return nil
            case .topLeft:     return NSPoint(x: 0, y: doc.height - clip.height)
            case .imageCenter: return NSPoint(x: (doc.width  - clip.width)/2,  y: (doc.height - clip.height)/2)
            case .visibleCenter:
                let vis = sv.contentView.bounds
                let cInView = CGPoint(x: vis.midX, y: vis.midY)
                let cInDoc  = sv.contentView.convert(cInView, to: docView)
                return NSPoint(x: cInDoc.x - vis.width/2, y: cInDoc.y - vis.height/2)
            case .cursor:
                guard let win = sv.window else { return nil }
                let mouseScreen = NSEvent.mouseLocation
                let mouseWin    = win.convertPoint(fromScreen: mouseScreen)
                let mouseScroll = sv.convert(mouseWin, from: nil)
                let mouseDoc    = sv.contentView.convert(mouseScroll, to: docView)
                return NSPoint(x: mouseDoc.x - clip.width/2, y: mouseDoc.y - clip.height/2)
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


/// 仅在“不可滚动的轴”上做最小尺寸约束以居中；可滚动轴不加约束，保证贴边
struct CenterBox: ViewModifier {
    let contentSize: CGSize
    let clipSize: CGSize
    let needH: Bool
    let needV: Bool

    func body(content: Content) -> some View {
        content
            .frame(
                minWidth:  needH ? nil : clipSize.width,
                minHeight: needV ? nil : clipSize.height,
                alignment: .center
            )
    }
}
extension View {
    func centerBox(contentSize: CGSize, clipSize: CGSize, needH: Bool, needV: Bool) -> some View {
        modifier(CenterBox(contentSize: contentSize, clipSize: clipSize, needH: needH, needV: needV))
    }
}

struct ScrollHelpers: View {
    let mode: RecenterMode
    let token: UUID
    let expectedDocSize: CGSize
    let onClipChange: (CGSize, Bool, Bool) -> Void
    let onNeedSnap: () -> Void                     // ✅ 新增

    var body: some View {
        Color.clear
            .background(
                ClipSizeProbe(
                    onChange: { clip, h, v in onClipChange(clip, h, v) },
                    onAxesBecameNonScrollable: { onNeedSnap() }   // ✅ 触发 snap
                )
            )
            .background(
                ScrollTuner(mode: mode, token: token, expectedDocSize: expectedDocSize)
            )
            .allowsHitTesting(false)
    }
}

struct ClipSizeProbe: NSViewRepresentable {
    var onChange: (_ clip: CGSize, _ needH: Bool, _ needV: Bool) -> Void
    var onAxesBecameNonScrollable: (() -> Void)? = nil   // ✅ 新增

    final class Coordinator {
        weak var scrollView: NSScrollView?
        var obs: NSKeyValueObservation?
        var lastClip: CGSize = .zero
        var lastNH = false
        var lastNV = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { attach(v, context) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        attach(nsView, context)
    }

    private func attach(_ v: NSView, _ context: Context) {
        guard context.coordinator.scrollView == nil else { return }
        var p: NSView? = v
        while let cur = p {
            if let sv = cur as? NSScrollView {
                context.coordinator.scrollView = sv
                context.coordinator.obs = sv.contentView.observe(\.bounds, options: [.new]) { _, _ in
                    emit(sv, context)
                }
                emit(sv, context) // 初次
                break
            }
            p = cur.superview
        }
    }

    private func emit(_ sv: NSScrollView, _ context: Context) {
        sv.layoutSubtreeIfNeeded()
        let clip = sv.contentView.bounds.size
        let doc  = sv.documentView?.bounds.size ?? .zero
        let eps: CGFloat = 0.5
        let needH = doc.width  > clip.width  + eps
        let needV = doc.height > clip.height + eps

        // 触发回调
        if clip != context.coordinator.lastClip || needH != context.coordinator.lastNH || needV != context.coordinator.lastNV {
            // ✅ 轴从可滚动→不可滚动，要求“收口”一次
            if (context.coordinator.lastNH == true && needH == false) ||
               (context.coordinator.lastNV == true && needV == false) {
                onAxesBecameNonScrollable?()
            }
            context.coordinator.lastClip = clip
            context.coordinator.lastNH = needH
            context.coordinator.lastNV = needV
            onChange(clip, needH, needV)
        }
    }
}
