//
//  PanMarqueeScrollView.swift
//  InfraView
//
//  Created by 王洋 on 4/11/2025.
//
// TODO: 切图的时候保留滚动条位置。
import SwiftUI
import AppKit

/// 一个包装 NSScrollView 的 SwiftUI 容器
/// 仅负责 UI 层级结构（不含任何功能逻辑）
struct PanMarqueeScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    @Binding var zoom: CGFloat
    let baseSize: CGSize
    let imagePixels: CGSize
    var onSelectionTap: ((CGPoint) -> Void)? = nil
    

    init(
        imagePixels: CGSize,
        baseSize: CGSize,
        zoom: Binding<CGFloat>,
        @ViewBuilder content: () -> Content) {
        self._zoom = zoom
            self.imagePixels = imagePixels
        self.baseSize = baseSize
        self.content = content()
    }
    
    final class Coordinator {
        var scrollView: NSScrollView?
        var hostingView: NSHostingView<Content>?
        var onSelectionTap: ((CGPoint) -> Void)?
        
        private var suppressMarquee = false
        
        var selectionStartInDoc: NSPoint?
        let selectionLayer = CAShapeLayer()
        var onFinished: ((CGRect) -> Void)?
        var onChanged: ((CGRect) -> Void)?
        
        var contentSize: CGSize = .zero
        var imagePixels: CGSize = .zero
        
        
        // 绑定进来，便于内部改 zoom
        var getZoom: (() -> CGFloat)?
        var setZoom: ((CGFloat) -> Void)?
        var baseSize: CGSize = .zero
        private var wheelMonitor: Any?
        
        var cachedClickRecognizer: NSClickGestureRecognizer?
        
        func installWheelMonitor() {
            guard wheelMonitor == nil else { return }
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                self?.handleWheel(e) ?? e
            }
        }
        deinit {
            if let m = wheelMonitor { NSEvent.removeMonitor(m) }
        }

        private func handleWheel(_ e: NSEvent) -> NSEvent? {
            guard let sv = scrollView,
                  e.modifierFlags.contains(.command),
                  let getZ = getZoom,
                  let setZ = setZoom,
                  let doc = sv.documentView else { return e }

            let factor: CGFloat = e.scrollingDeltaY > 0 ? 1.1 : (e.scrollingDeltaY < 0 ? 1/1.1 : 1)
            guard factor != 1 else { return e }

            let oldZ = max(0.01, getZ())
            let newZ = min(10.0, max(0.05, oldZ * factor))
            if abs(newZ - oldZ) < 1e-3 { return nil }

            // 记录锚点（鼠标位置）相对 doc 的归一化坐标
            let cv = sv.contentView
            let mouseInWin = e.locationInWindow
            let mouseInCV  = cv.convert(mouseInWin, from: nil)
            let mouseInDoc = cv.convert(mouseInCV, to: doc)
            let docW = max(doc.bounds.width, 1), docH = max(doc.bounds.height, 1)
            let anchorN = CGPoint(x: mouseInDoc.x / docW, y: mouseInDoc.y / docH)

            // 记录当前可视区域中心归一化坐标（作为备用）
            let fallbackN = normalizedCenter(in: sv)

            // 更新 zoom → 更新 document 尺寸
            setZ(newZ)

            // 根据“锚点”计算新原点
            guard let doc2 = sv.documentView else { return nil }
            let target = NSPoint(x: anchorN.x * doc2.bounds.width,
                                 y: anchorN.y * doc2.bounds.height)
            var newOrigin = NSPoint(x: target.x - cv.bounds.width / 2,
                                    y: target.y - cv.bounds.height / 2)
            newOrigin = clampOrigin(newOrigin, cv: cv, doc: doc2)

            //cv.scroll(to: newOrigin)
            sv.reflectScrolledClipView(cv)
            return nil
        }

        
        
        @objc func handlePan(_ g: NSPanGestureRecognizer) {
            guard let sv = scrollView, let doc = sv.documentView else { return }
            let cv = sv.contentView
            guard g.state == .began || g.state == .changed else { return }

            let t = g.translation(in: cv)
            g.setTranslation(.zero, in: cv)
            var o = cv.bounds.origin
            o.x -= t.x; o.y -= t.y

            let dw = doc.bounds.width, dh = doc.bounds.height
            let cw = cv.bounds.width, ch = cv.bounds.height

            // 不能滚就锁定居中
            o.x = (dw <= cw) ? (dw - cw)/2 : min(max(0, o.x), dw - cw)
            o.y = (dh <= ch) ? (dh - ch)/2 : min(max(0, o.y), dh - ch)

            cv.scroll(to: o)
            sv.reflectScrolledClipView(cv)
        }
        
        @objc func handleSelectionClick(_ g: NSClickGestureRecognizer) {
            guard let sv = scrollView, let doc = sv.documentView else { return }
            guard let path = selectionLayer.path else { return }
            let pDoc = g.location(in: doc)  // overlay 坐标
            if path.contains(pDoc) {
                    onSelectionTap?(pDoc)                // 交给外部放大
            } else {
                // 点在框外：清除选框
                selectionLayer.path = nil
            }
        }

        func restrictP(p: NSPoint) -> NSPoint {
            // 限制 p 在 image 内
            let z = max(0.01, getZoom?() ?? 1)
            return NSPoint(x: min(max(0, p.x), baseSize.width * z),
                           y: min(max(0, p.y), baseSize.height * z))
        }
        @objc func handleMarquee(_ g: NSPanGestureRecognizer) {
            //scrollView
            // ├── contentView  ← 负责显示可视区域
            // │     └── documentView  ← 实际内容（可能很大，可以滚动）
            guard let sv = scrollView,
                  let doc = sv.documentView else { return }
            let cv = sv.contentView
            // 把手势位置从 contentView 坐标转到 documentView 坐标
            var p = cv.convert(g.location(in: cv), to: doc)
            p = restrictP(p: p)
            switch g.state {
            case .began:
                if let path = selectionLayer.path, path.contains(p) {
                    suppressMarquee = true
                    return
                }
                suppressMarquee = false
                selectionStartInDoc = p
                ensureSelectionLayer(on: doc)                 // 准备 overlay
                if let s = selectionStartInDoc {
                    let snapped = snapRectToPixels(start: s, end: p, imagePixels: imagePixels)
                    drawSelection(rectInDoc: snapped.rectDoc)
                    // 确保 selectionLayer 在最上层
                    if let superlayer = selectionLayer.superlayer {
                        selectionLayer.removeFromSuperlayer()
                        superlayer.addSublayer(selectionLayer)
                    }
                    onChanged?(snapped.rectPx)
                }
            case .changed:
                guard !suppressMarquee, let s = selectionStartInDoc else { return }
                let snapped = snapRectToPixels(start: s, end: p, imagePixels: imagePixels)
                drawSelection(rectInDoc: snapped.rectDoc)
                onChanged?(snapped.rectPx)
            case .ended, .cancelled:
                if suppressMarquee {
                    onSelectionTap?(p)
                    suppressMarquee = false
                    return
                }
                guard let s = selectionStartInDoc else { return }
                let snapped = snapRectToPixels(start: s, end: p, imagePixels: imagePixels)
                drawSelection(rectInDoc: snapped.rectDoc)
                onFinished?(snapped.rectPx)
                selectionStartInDoc = nil
            default:
                break
            }
        }
        // 轻量工具们 —— 最小实现
        private func normalizedRect(_ a: NSPoint, _ b: NSPoint) -> CGRect {
            let x1 = min(a.x, b.x), y1 = min(a.y, b.y)
            let x2 = max(a.x, b.x), y2 = max(a.y, b.y)
            return CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
        }
        private func ensureSelectionLayer(on doc: NSView) {
            if selectionLayer.superlayer == nil {
                doc.wantsLayer = true
                selectionLayer.fillColor = nil
                selectionLayer.strokeColor = NSColor.controlAccentColor.cgColor
                selectionLayer.lineWidth = 1
                selectionLayer.lineDashPattern = [4, 3]
                doc.layer?.addSublayer(selectionLayer)
                //selectionLayer.isGeometryFlipped = true
                if cachedClickRecognizer == nil {
                    let click = NSClickGestureRecognizer(target: self, action: #selector(handleSelectionClick(_:)))
                    doc.addGestureRecognizer(click)
                    cachedClickRecognizer = click
                }
            }
        }
        private func drawSelection(rectInDoc: CGRect) {
            guard rectInDoc.width > 0, rectInDoc.height > 0 else {
                selectionLayer.path = nil
                return
            }
            let path = CGMutablePath()
            path.addRect(rectInDoc)
            selectionLayer.path = path // 只描边；fillColor 请保持为 nil
        }
        private func snapRectToPixels(start sDoc: NSPoint,
                                      end eDoc: NSPoint,
                                      imagePixels: CGSize) -> (rectDoc: CGRect, rectPx: CGRect) {
            let z = getZoom?() ?? 1
            let contentSize = CGSize(width: baseSize.width * z, height: baseSize.height * z)

            let sx = max(0.0001, imagePixels.width  / max(0.0001, contentSize.width))
            let sy = max(0.0001, imagePixels.height / max(0.0001, contentSize.height))

            // 文档点 → 像素
            let sPx = NSPoint(x: sDoc.x * sx, y: sDoc.y * sy)
            let ePx = NSPoint(x: eDoc.x * sx, y: eDoc.y * sy)

            // 规范化 + 量子化（贴像素网格）
            let x0 = floor(min(sPx.x, ePx.x))
            let y0 = floor(min(sPx.y, ePx.y))
            let x1 = floor(max(sPx.x, ePx.x))
            let y1 = floor(max(sPx.y, ePx.y))

            var rPx = CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))

            // 夹紧到图片像素边界
            rPx.origin.x = max(0, min(rPx.origin.x, imagePixels.width))
            rPx.origin.y = max(0, min(rPx.origin.y, imagePixels.height))
            rPx.size.width  = max(0, min(rPx.maxX, imagePixels.width)  - rPx.origin.x)
            rPx.size.height = max(0, min(rPx.maxY, imagePixels.height) - rPx.origin.y)

            // 像素 → 文档点（用于画框）
            let rDoc = CGRect(x: rPx.origin.x / sx,
                              y: rPx.origin.y / sy,
                              width:  rPx.size.width  / sx,
                              height: rPx.size.height / sy)
            return (rDoc, rPx)
        }
    }
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        // 外层滚动视图
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()

        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // SwiftUI 的 View 用 NSHostingView 包起来变成 NSView，才能放入 documentView
        let hostingView = NSHostingView(rootView: content)
        //hostingView.frame.size = contentSize
        // 下面这个有必要吗？
        //hostingView.sizingOptions = [.intrinsicContentSize]   // ← 让 documentView 按 SwiftUI 内在尺寸走

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView
        
        context.coordinator.scrollView = scrollView
        context.coordinator.hostingView = hostingView
        context.coordinator.onSelectionTap = onSelectionTap

        context.coordinator.imagePixels = imagePixels
        context.coordinator.baseSize = baseSize
        context.coordinator.getZoom = { self.zoom }
        context.coordinator.setZoom = { new in self.zoom = new }   // 外层 @State 更新
        context.coordinator.installWheelMonitor()
        
        // （以后会在这里添加：overlayView + 手势等）
        // ✅ 添加右键拖拽手势
        let pan = NSPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.buttonMask = 0x2   // 右键（secondary button）
        scrollView.contentView.addGestureRecognizer(pan)
        
        //✅ 添加左键画框
        let mar = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMarquee(_:)))
        mar.buttonMask = 0x1
        scrollView.contentView.addGestureRecognizer(mar)
        
        return scrollView
    }
    // 每次切图/尺寸变化都会走这里：同步更新，绝不异步
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let hv = context.coordinator.hostingView else { return }
        
        let nCenter = normalizedCenter(in: nsView)
        hv.rootView = content
        
        
        //hv.layoutSubtreeIfNeeded()
        //nsView.reflectScrolledClipView(nsView.contentView)
        context.coordinator.imagePixels = imagePixels
        context.coordinator.baseSize = baseSize
        //context.coordinator.updateDocSizeForZoom()
        
        restoreCenter(nCenter, in: nsView)
    }
}


/// 当文档内容比可视区域小时，让内容居中显示的 ClipView。
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let docView = self.documentView else { return rect }

        let docFrame = docView.frame
        let clipSize = self.bounds.size

        // 如果文档比视口小，则让它在该方向居中
        if docFrame.width < clipSize.width {
            rect.origin.x = (docFrame.width - clipSize.width) / 2.0
        }
        if docFrame.height < clipSize.height {
            rect.origin.y = (docFrame.height - clipSize.height) / 2.0
        }
        return rect
    }
    override func scrollWheel(with event: NSEvent) {
        // 只有按下 ⌘ 时才拦截；否则交给默认滚动
        if event.modifierFlags.contains(.command) {
            return  // 吞掉事件
        }
        super.scrollWheel(with: event)  // 没按 ⌘ 时放行
    }
}


func pixelRect(from selectionDoc: CGRect,
               contentSize: CGSize,          // 当前显示尺寸（点）
               imagePixels: CGSize) -> CGRect {

    guard contentSize.width  > 0, contentSize.height > 0 else { return .zero }

    let sx = imagePixels.width  / contentSize.width
    let sy = imagePixels.height / contentSize.height

    var r = CGRect(x: selectionDoc.minX * sx,
                   y: selectionDoc.minY * sy,
                   width:  selectionDoc.width  * sx,
                   height: selectionDoc.height * sy)

    // 可选：取整并夹紧在 0…像素边界
    r.origin.x = max(0, floor(r.origin.x))
    r.origin.y = max(0, floor(r.origin.y))
    r.size.width  = max(0, floor(r.maxX) - r.origin.x)
    r.size.height = max(0, floor(r.maxY) - r.origin.y)
    r.size.width  = min(r.width,  imagePixels.width  - r.origin.x)
    r.size.height = min(r.height, imagePixels.height - r.origin.y)
    return r
}



/// 归一化位置：以 document 可视中心点作归一化锚 (0...1)
func normalizedCenter(in sv: NSScrollView) -> CGPoint {
    guard let doc = sv.documentView else { return .zero }
    let cv = sv.contentView
    let vis = cv.bounds
    let center = NSPoint(x: vis.midX, y: vis.midY)
    let w = max(doc.bounds.width, 1)
    let h = max(doc.bounds.height, 1)
    return CGPoint(x: center.x / w, y: center.y / h)
}

/// 根据归一化中心点恢复滚动位置
func restoreCenter(_ n: CGPoint, in sv: NSScrollView) {
    guard let doc = sv.documentView else { return }
    let cv = sv.contentView
    let target = NSPoint(x: n.x * doc.bounds.width,
                         y: n.y * doc.bounds.height)
    let o = NSPoint(x: target.x - cv.bounds.width  / 2.0,
                    y: target.y - cv.bounds.height / 2.0)
    cv.scroll(to: clampOrigin(o, cv: cv, doc: doc))
    sv.reflectScrolledClipView(cv)
}

/// 将原点限制在合法范围并处理“小图居中”的情形
private func clampOrigin(_ o: NSPoint, cv: NSClipView, doc: NSView) -> NSPoint {
    var o = o
    let dw = doc.bounds.width, dh = doc.bounds.height
    let cw = cv.bounds.width, ch = cv.bounds.height
    o.x = (dw <= cw) ? (dw - cw)/2 : min(max(0, o.x), dw - cw)
    o.y = (dh <= ch) ? (dh - ch)/2 : min(max(0, o.y), dh - ch)
    return o
}


