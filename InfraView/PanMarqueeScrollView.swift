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
    var colorProvider: ((Int, Int) -> NSColor)? = nil

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
        let selectionLayer = SelectionOverlay()
        var onFinished: ((CGRect) -> Void)?
        var onChanged: ((CGRect) -> Void)?
    
        var imagePixels: CGSize = .zero
        
        // 绑定进来，便于内部改 zoom
        var getZoom: (() -> CGFloat)?
        var setZoom: ((CGFloat) -> Void)?
        var baseSize: CGSize = .zero
        
        // Avoid alwasy create new click recognizers
        var cachedClickRecognizer: NSClickGestureRecognizer?
        var cachedDoubleClickRecognizer: NSClickGestureRecognizer?

        var mouseDownMonitor: Any?
        var getColorAtPx: ((Int, Int) -> NSColor?)?


        
        func handleWheel(_ e: NSEvent) {
            guard let sv = scrollView,
                  e.hasCommand,
                  let getZ = getZoom,
                  let setZ = setZoom,
                  let doc = sv.documentView else { return }

            let factor: CGFloat = e.scrollingDeltaY > 0 ? 1.1 : (e.scrollingDeltaY < 0 ? 1/1.1 : 1)
            guard factor != 1 else { return }

            let oldZ = max(0.01, getZ())
            let newZ = min(10.0, max(0.05, oldZ * factor))
            if abs(newZ - oldZ) < 1e-3 { return }

            // 记录锚点（鼠标位置）相对 doc 的归一化坐标
            let cv = sv.contentView
            let mouseInWin = e.locationInWindow
            let mouseInCV  = cv.convert(mouseInWin, from: nil)
            let mouseInDoc = cv.convert(mouseInCV, to: doc)
            let docW = max(doc.bounds.width, 1), docH = max(doc.bounds.height, 1)
            let anchorN = CGPoint(x: mouseInDoc.x / docW, y: mouseInDoc.y / docH)


            // 更新 zoom → 更新 document 尺寸
            setZ(newZ)
            
            // 根据“锚点”计算新原点
            guard let doc2 = sv.documentView else { return }
            let target = NSPoint(x: anchorN.x * doc2.bounds.width,
                                 y: anchorN.y * doc2.bounds.height)
            var newOrigin = NSPoint(x: target.x - cv.bounds.width / 2,
                                    y: target.y - cv.bounds.height / 2)
            newOrigin = clampOrigin(newOrigin, cv: cv, doc: doc2)

            //cv.scroll(to: newOrigin)
            sv.reflectScrolledClipView(cv)
            
            // 缩放后重绘选框
            if let rPx = selectionLayer.currentSelectionPx, let m = makeMapper() {
                let originDoc = m.pxToDoc(rPx.origin)
                let sizeDoc   = CGSize(width: rPx.size.width / m.sx, height: rPx.size.height / m.sy)
                let rDoc      = CGRect(origin: originDoc, size: sizeDoc)
                selectionLayer.updateInDoc(rectInDoc: rDoc)
            }

        }

        @objc func handlePan(_ g: NSPanGestureRecognizer) {
            guard let sv = scrollView, let doc = sv.documentView else { return }
            let cv = sv.contentView
            switch g.state {
            case .began:
                NSCursor.closedHand.push()
            case .ended, .cancelled:
                NSCursor.pop()
            default:
                break
            }
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
        
        @objc func handleZoomClick(_ g: NSClickGestureRecognizer) {
            guard let sv = scrollView, let doc = sv.documentView else { return }
            guard let path = selectionLayer.layer.path else { return }
            let pDoc = g.location(in: doc)  // overlay 坐标
            if path.contains(pDoc) {
                    onSelectionTap?(pDoc)                // 交给外部放大
            } else {
                selectionLayer.clear()
                if let win = scrollView?.window {
                    let base = baseTitle ?? cleanBaseTitle(win.title)
                    win.title = base
                }
            }
        }
        @objc func handleDoubleClick(_ g: NSClickGestureRecognizer) {
            guard g.state == .ended else { return }
            g.view?.window?.toggleFullScreen(nil)
        }
        func restrictP(p: NSPoint) -> NSPoint {
            // 限制 p 在 image 内
            guard let m = makeMapper() else { return p }
            let clamped = m.clampDocPoint(p)
            /*
            return NSPoint(x: min(max(0, p.x), baseSize.width * z),
                           y: min(max(0, p.y), baseSize.height * z))
            */
            return NSPoint(x: clamped.x, y: clamped.y)
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
                if let path = selectionLayer.layer.path, path.contains(p) {
                    suppressMarquee = true
                    return
                }
                suppressMarquee = false
                NSCursor.crosshair.push()
                selectionStartInDoc = p
                ensureSelectionLayer(on: doc)                 // 准备 overlay
                if let s = selectionStartInDoc, let m = makeMapper() {
                    let snapped = m.snapRectToPixels(docStart: s, docEnd: p)
                    selectionLayer.update(snapped: snapped)
                    onChanged?(snapped.rectPx)
                }
            case .changed:
                guard !suppressMarquee, let s = selectionStartInDoc, let m = makeMapper() else { return }
                let snapped = m.snapRectToPixels(docStart: s, docEnd: p)
                
                selectionLayer.update(snapped: snapped)
                onChanged?(snapped.rectPx)
                
                let w = Int(snapped.rectPx.width.rounded())
                let h = Int(snapped.rectPx.height.rounded())
                let x = Int(snapped.rectPx.origin.x.rounded())
                let y = Int(snapped.rectPx.origin.y.rounded())
                if let win = scrollView?.window {
                    if w > 0 && h > 0 {
                        win.title = "XY:(\(x),\(y))(\(w)x\(h) pixels, \(ratioText(w,h)))"
                    } else {
                        // 没有有效选框时，拖动中标题可以清空为纯坐标或直接用空
                        win.title = "XY:(\(x),\(y))"
                    }
                }
            case .ended, .cancelled:
                if suppressMarquee {
                    onSelectionTap?(p)
                    suppressMarquee = false
                    return
                }
                NSCursor.pop()
                guard let s = selectionStartInDoc, let m = makeMapper() else { return }
                let snapped = m.snapRectToPixels(docStart: s, docEnd: p)
                selectionLayer.update(snapped: snapped)
                onFinished?(snapped.rectPx)
                selectionStartInDoc = nil
                let w = Int(snapped.rectPx.width.rounded())
                let h = Int(snapped.rectPx.height.rounded())
                let x = Int(snapped.rectPx.origin.x.rounded())
                let y = Int(snapped.rectPx.origin.y.rounded())
                if let win = scrollView?.window {
                    let base = baseTitle ?? cleanBaseTitle(win.title)
                    if w > 0 && h > 0 {
                        win.title = "\(base) — Selection: \(x), \(y); \(w) x \(h); \(ratioText(w,h))"
                    } else {
                        win.title = base
                    }
                }
            default:
                break
            }
        }

        private func ensureSelectionLayer(on doc: NSView) {
            selectionLayer.attachIfNeeded(to: doc)
            if cachedDoubleClickRecognizer == nil {
                let dbl = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
                dbl.numberOfClicksRequired = 2
                dbl.buttonMask = 0x1 // 左键
                doc.addGestureRecognizer(dbl)
                cachedDoubleClickRecognizer = dbl
            }
            if cachedClickRecognizer == nil {
                let click = NSClickGestureRecognizer(target: self, action: #selector(handleZoomClick(_:)))
                doc.addGestureRecognizer(click)
                cachedClickRecognizer = click
            }
        }
        
        private var baseTitle: String? // 记住文件名
        private func cleanBaseTitle(_ t: String) -> String {
            var s = t
            s = s.replacingOccurrences(of: #" — XY:.*$"#,         with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: #" — Selection:.*$"#,  with: "", options: .regularExpression)
            return s
        }
        private func ratioText(_ w: Int, _ h: Int) -> String {
            guard w > 0, h > 0 else { return "-" }
            return String(format: "%.4f", Double(w) / Double(h))
        }
        
        func installMouseDownMonitor() {
            // 监听左键按下，但不“消费”事件
            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
                

                
                guard let self,
                      let sv = self.scrollView,
                      let doc = sv.documentView else { return e }

                let cv   = sv.contentView
                
                
                
                //
                if selectionLayer.layer.path != nil {
                    let docRectInCV = cv.convert(doc.bounds, from: doc)
                    let pInCV = cv.convert(e.locationInWindow, from: nil)
                    if !docRectInCV.contains(pInCV) {
                        selectionLayer.clear()
                        if let win = sv.window {
                            let base = baseTitle ?? cleanBaseTitle(win.title)
                            win.title = base
                        }
                    }
                }
                
                
                
                
                let pInCV = cv.convert(e.locationInWindow, from: nil)
                var pDoc  = cv.convert(pInCV, to: doc)
                pDoc = self.restrictP(p: pDoc)

                guard let m = self.makeMapper() else { return e }
                let pPx = m.docToPx(pDoc)
                let px = Int(floor(pPx.x))
                let py = Int(floor(pPx.y))
                let x  = max(0, min(px, Int(self.imagePixels.width)  - 1))
                let y  = max(0, min(py, Int(self.imagePixels.height) - 1))

                if let win = sv.window {
                    self.baseTitle = self.cleanBaseTitle(win.title)   // 记住文件名

                    if let c = self.getColorAtPx?(x, y)?.usingColorSpace(.sRGB) {
                        let r = Int(round(c.redComponent   * 255))
                        let g = Int(round(c.greenComponent * 255))
                        let b = Int(round(c.blueComponent  * 255))
                        let a = Int(round(c.alphaComponent * 255))
                        let html = String(format: "#%02X%02X%02X", r, g, b)
                        win.title = "XY:(\(x),\(y)) - RGB:(\(r),\(g),\(b),a:\(a)), HTML:(\(html))"
                    } else {
                        // 颜色取不到也更新标题（至少有 XY）
                        win.title = "XY:(\(x),\(y))" // - (no color)"
                    }
                }
                return e  // 不拦截事件，后续拖拽/双击照常工作
            }
        }
    }
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        // 外层滚动视图
        let scrollView = NSScrollView()
        let clipView = CenteringClipView()
        scrollView.contentView = clipView

        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // SwiftUI 的 View 用 NSHostingView 包起来变成 NSView，才能放入 documentView
        let hostingView = NSHostingView(rootView: content)

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView
        
        context.coordinator.scrollView = scrollView
        context.coordinator.hostingView = hostingView
        context.coordinator.onSelectionTap = onSelectionTap

        context.coordinator.imagePixels = imagePixels
        context.coordinator.baseSize = baseSize
        context.coordinator.getZoom = { self.zoom }
        context.coordinator.setZoom = { new in self.zoom = new }   // 外层 @State 更新
        // ✅ 添加右键拖拽手势
        let pan = NSPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.buttonMask = 0x2   // 右键（secondary button）
        scrollView.contentView.addGestureRecognizer(pan)
        
        // ✅ 添加左键画框
        let mar = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMarquee(_:)))
        mar.buttonMask = 0x1
        scrollView.contentView.addGestureRecognizer(mar)
        
        // ✅ 添加滚轮缩放
        clipView.onCommandScroll = { [weak coord = context.coordinator] e in
            coord?.handleWheel(e)
        }
        
        // ✅ 安装“按下就触发”的手势（不会与左键拖选框冲突）
        context.coordinator.getColorAtPx = { x, y in self.colorProvider?(x, y) } // ← 新增
        context.coordinator.installMouseDownMonitor()
        return scrollView
    }
    // 每次切图/尺寸变化都会走这里：同步更新，绝不异步
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let hv = context.coordinator.hostingView else { return }
        hv.rootView = content
        //hv.layoutSubtreeIfNeeded()
        //nsView.reflectScrolledClipView(nsView.contentView)
        context.coordinator.imagePixels = imagePixels
        context.coordinator.baseSize = baseSize
        //context.coordinator.updateDocSizeForZoom()
    }
}


/// 当文档内容比可视区域小时，让内容居中显示的 ClipView。
final class CenteringClipView: NSClipView {
    var onCommandScroll: ((NSEvent) -> Void)?
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
        if event.hasCommand
        {
            onCommandScroll?(event)
            return  // 吞掉事件
        }
        super.scrollWheel(with: event)  // 没按 ⌘ 时放行
    }
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




struct PixelMapper {
    let baseSize: CGSize      // 图像“基准显示”尺寸（pt）
    let zoom: CGFloat         // 当前缩放
    let imagePixels: CGSize   // 图像像素尺寸（px）

    var contentSize: CGSize { .init(width: baseSize.width * zoom,
                                    height: baseSize.height * zoom) }

    var sx: CGFloat { max(0.0001, imagePixels.width  / max(0.0001, contentSize.width))  }
    var sy: CGFloat { max(0.0001, imagePixels.height / max(0.0001, contentSize.height)) }

    func docToPx(_ p: CGPoint) -> CGPoint { .init(x: p.x * sx, y: p.y * sy) }
    func pxToDoc(_ p: CGPoint) -> CGPoint { .init(x: p.x / sx, y: p.y / sy) }

    func snapRectToPixels(docStart sDoc: CGPoint, docEnd eDoc: CGPoint) -> (rectDoc: CGRect, rectPx: CGRect) {
        // doc → px
        let sPx = docToPx(sDoc), ePx = docToPx(eDoc)
        // 规范化 + 量子化
        let x0 = floor(min(sPx.x, ePx.x)), y0 = floor(min(sPx.y, ePx.y))
        let x1 = floor(max(sPx.x, ePx.x)), y1 = floor(max(sPx.y, ePx.y))
        var rPx = CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
        // 夹紧到图像边界
        rPx.origin.x = max(0, min(rPx.origin.x, imagePixels.width))
        rPx.origin.y = max(0, min(rPx.origin.y, imagePixels.height))
        rPx.size.width  = max(0, min(rPx.maxX, imagePixels.width)  - rPx.origin.x)
        rPx.size.height = max(0, min(rPx.maxY, imagePixels.height) - rPx.origin.y)
        // px → doc
        let rDoc = CGRect(origin: pxToDoc(rPx.origin),
                          size:   .init(width: rPx.width / sx, height: rPx.height / sy))
        return (rDoc, rPx)
    }

    func clampDocPoint(_ p: CGPoint) -> CGPoint {
        let w = contentSize.width, h = contentSize.height
        return .init(x: min(max(0, p.x), w), y: min(max(0, p.y), h))
    }
}
extension PanMarqueeScrollView.Coordinator {
    func makeMapper() -> PixelMapper? {
        guard let getZ = getZoom else { return nil }
        return PixelMapper(baseSize: baseSize, zoom: getZ(), imagePixels: imagePixels)
    }
}
extension NSEvent {
    var hasCommand: Bool {
        //e.modifierFlags.contains(.command),
        modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
    }
}






final class SelectionOverlay {
    let layer = CAShapeLayer()
    var currentSelectionPx: CGRect?

    init() {
        layer.fillColor = nil
        layer.strokeColor = NSColor.controlAccentColor.cgColor
        layer.lineWidth = 1
        layer.lineDashPattern = [4, 3]
        layer.zPosition = 1_000_000
    }
    func attachIfNeeded(to doc: NSView) {
        doc.wantsLayer = true
        guard let L = doc.layer else { return }
        if layer.superlayer !== L { layer.removeFromSuperlayer(); L.addSublayer(layer) }
    }
    func updateInDoc(rectInDoc: CGRect?) {
        guard let r = rectInDoc, r.width > 0, r.height > 0 else { layer.path = nil; return }
        let path = CGMutablePath(); path.addRect(r)
        layer.path = path
    }
    func update(snapped: (rectDoc: CGRect, rectPx: CGRect)) {
        updateInDoc(rectInDoc: snapped.rectDoc)
        currentSelectionPx = snapped.rectPx
    }
    func clear() {
        layer.path = nil
        currentSelectionPx = nil
    }
}
