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
        let overlayView = NSView()
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
                  e.modifierFlags.contains(.command) else { return e } // 非 ⌘ 滚轮 → 放行

            // 缩放因子（滚轮向上放大、向下缩小）
            let delta = e.scrollingDeltaY      // 正负取决于系统设置；可按需取反
            let factor: CGFloat
            if delta > 0 {
                factor = 1.1
            } else if delta < 0 {
                factor = 1 / 1.1
            } else {
                return e
            }

            guard let getZ = getZoom, let setZ = setZoom else { return e }
            let oldZ = max(0.01, getZ())
            let newZ = min(10.0, max(0.05, oldZ * factor))
            if abs(newZ - oldZ) < 1e-6 { return nil }  // 吃掉事件即可

            // 以鼠标在 contentView 的位置为锚点
            let cv = sv.contentView
            let doc = sv.documentView!
            let mouseInWin = e.locationInWindow
            let mouseInCV  = cv.convert(mouseInWin, from: nil)
            let pDocBefore = cv.convert(mouseInCV, to: doc) // 文档坐标中的“锚点”

            // 先更新 zoom（外层会据此重建 ZoomedContent 并更新 documentView.size）
            setZ(newZ)

            // 计算缩放后的文档尺寸 & 同一锚点的新文档坐标
            let oldSize = CGSize(width: baseSize.width * oldZ, height: baseSize.height * oldZ)
            let newSize = CGSize(width: baseSize.width * newZ, height: baseSize.height * newZ)
            let sx = newSize.width  / max(oldSize.width,  0.0001)
            let sy = newSize.height / max(oldSize.height, 0.0001)
            let pDocAfter = NSPoint(x: pDocBefore.x * sx, y: pDocBefore.y * sy)

            // 让“锚点”在缩放后仍落在鼠标下：origin' = pDocAfter - mouseInCV
            var o = NSPoint(x: pDocAfter.x - mouseInCV.x, y: pDocAfter.y - mouseInCV.y)

            // 夹紧 + 小图时轴向居中
            let cw = cv.bounds.width, ch = cv.bounds.height
            let dw = newSize.width,   dh = newSize.height
            o.x = (dw <= cw) ? (dw - cw)/2 : min(max(0, o.x), dw - cw)
            o.y = (dh <= ch) ? (dh - ch)/2 : min(max(0, o.y), dh - ch)

            // 应用滚动定位（此时 documentView 已在下一轮更新为新尺寸；
            // 这里先定位，SwiftUI 更新后会再次校正一次，视觉无跳动）
            cv.scroll(to: o)
            sv.reflectScrolledClipView(cv)

            return nil // 吃掉 ⌘ 滚轮，避免被当普通滚动
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
        @objc func handleOverlayClick(_ g: NSClickGestureRecognizer) {
            guard let overlay = overlayView.layer, let path = selectionLayer.path else { return }
            let pOverlay = g.location(in: overlayView)  // overlay 坐标

            if path.contains(pOverlay) {
                // 点在框内：把点位换到文档坐标后回调给你做放大
                if let doc = overlayView.superview {     // documentView 就是 overlay 的 superview
                    let pDoc = overlayView.convert(pOverlay, to: doc)
                    onSelectionTap?(pDoc)                // 交给外部放大
                }
            } else {
                // 点在框外：清除选框
                selectionLayer.path = nil
            }
        }
        func normalizePoint(p: CGSize) {
            
        }
        @objc func handleMarquee(_ g: NSPanGestureRecognizer) {
            //scrollView
            // ├── contentView  ← 负责显示可视区域
            // │     └── documentView  ← 实际内容（可能很大，可以滚动）
            guard let sv = scrollView,
                  let doc = sv.documentView else { return }
            let cv = sv.contentView
            // 把手势位置从 contentView 坐标转到 documentView 坐标
            let p = cv.convert(g.location(in: cv), to: doc)
            let pOverlay = overlayView.convert(p, from: doc)
            
            switch g.state {
            case .began:
                if let path = selectionLayer.path, path.contains(pOverlay) {
                    suppressMarquee = true
                    return
                }
                suppressMarquee = false
                selectionStartInDoc = p
                ensureOverlay(on: doc)                 // 准备 overlay
                if let s = selectionStartInDoc {
                    let snapped = snapRectToPixels(start: s, end: p, imagePixels: imagePixels)
                    drawSelection(rectInDoc: snapped.rectDoc)
                    onChanged?(snapped.rectPx)
                }
                //drawSelection(from: p, to: p)          // 先画一个 0 大小的框
            case .changed:
                guard !suppressMarquee, let s = selectionStartInDoc else { return }
                let snapped = snapRectToPixels(start: s, end: p, imagePixels: imagePixels)
                drawSelection(rectInDoc: snapped.rectDoc)
                onChanged?(snapped.rectPx)
                //drawSelection(from: s, to: p)
            case .ended, .cancelled:
                if suppressMarquee {
                    onSelectionTap?(p)
                    suppressMarquee = false
                    return
                }
                guard let s = selectionStartInDoc else { return }
                let snapped = snapRectToPixels(start: s, end: p,
                                                    
                                                       imagePixels: imagePixels)
                print(s)
                print(snapped)
                let r = normalizedRect(s, p)
                /*
                // 清掉
                //drawSelection(from: .zero, to: .zero)
                selectionStartInDoc = nil
                // 把结果回调给 SwiftUI（可选）
                */
                drawSelection(rectInDoc: snapped.rectDoc)
                onFinished?(r)
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
        private func ensureOverlay(on doc: NSView) {
            if overlayView.superview == nil {
                overlayView.wantsLayer = true
                overlayView.layer?.backgroundColor = NSColor.clear.cgColor
                overlayView.frame = doc.bounds
                overlayView.autoresizingMask = [.width, .height]   // 跟随文档大小
                doc.addSubview(overlayView)

                selectionLayer.fillColor = nil
                    // NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
                selectionLayer.strokeColor = NSColor.controlAccentColor.cgColor
                selectionLayer.lineWidth = 1
                selectionLayer.lineDashPattern = [4, 3]
                overlayView.layer?.addSublayer(selectionLayer)
                //selectionLayer.isGeometryFlipped = true
                let click = NSClickGestureRecognizer(target: self, action: #selector(handleOverlayClick(_:)))
                overlayView.addGestureRecognizer(click)
            }
        }
        /*
        private func drawSelection(from a: NSPoint, to b: NSPoint) {
            let rDoc = normalizedRect(a, b)
            guard let doc = overlayView.superview else { return }
            let rOverlay = overlayView.convert(rDoc, from: doc)
            let path = CGMutablePath()
            path.addRect(rOverlay)
            selectionLayer.path = rOverlay.isEmpty ? nil : path
        }*/
        private func drawSelection(rectInDoc: CGRect) {
            guard rectInDoc.width > 0, rectInDoc.height > 0 else {
                selectionLayer.path = nil
                return
            }
            // overlay 的父视图就是 documentView
            guard let doc = overlayView.superview else { return }
            let rOverlay = overlayView.convert(rectInDoc, from: doc)

            let path = CGMutablePath()
            path.addRect(rOverlay)
            selectionLayer.path = path          // 只描边；fillColor 请保持为 nil
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

        // SwiftUI 内容用 NSHostingView 包起来，放入 documentView
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
        hv.rootView = content
        
        //hv.layoutSubtreeIfNeeded()
        //nsView.reflectScrolledClipView(nsView.contentView)
        //context.coordinator.imagePixels = imagePixels
        //context.coordinator.baseSize = baseSize
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
