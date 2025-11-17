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
    let viewerVM: ViewerViewModel

    init(
            imagePixels: CGSize,
            baseSize: CGSize,
            zoom: Binding<CGFloat>,
            viewerVM: ViewerViewModel,
            
            @ViewBuilder content: () -> Content) {
        self._zoom = zoom
        self.imagePixels = imagePixels
        self.baseSize = baseSize
        self.viewerVM = viewerVM
        self.content = content()
    }
    
    final class Coordinator {
        var scrollView: NSScrollView?
        var hostingView: NSHostingView<Content>?
        weak var viewerVM: ViewerViewModel?
        
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
        var mouseUpMonitor: Any?
        var mouseMoveMonitor: Any?
        var rotateObserver: NSObjectProtocol?
        var selectAllObserver: NSObjectProtocol?
        var cropObserver: NSObjectProtocol?
        var saveObserver: NSObjectProtocol?
        
        var resizingEdge: Edge?
        
        init() {
            rotateObserver = NotificationCenter.default.addObserver(
                forName: .infraRotate,
                object: nil,
                queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, let win = viewerVM?.window, win.isKeyWindow else { return }
                        self.clearSelection(updateVM: true, restoreTitle: true)
                    }
            }
            selectAllObserver = NotificationCenter.default.addObserver(
                forName: .infraSelectAll,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSelectAll()
                }
            }
            cropObserver = NotificationCenter.default.addObserver(
                forName: .infraCrop,
                object: nil,
                queue: .main
            ) { [weak self] note in
                Task { @MainActor [weak self] in
                    self?.handleCrop()
                }
            }
            saveObserver = NotificationCenter.default.addObserver(
                forName: .infraSave,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.viewerVM?.saveCurrentImage()
                }
            }
        }
        deinit {
            if let m = mouseDownMonitor { NSEvent.removeMonitor(m) }
            if let m = mouseUpMonitor   { NSEvent.removeMonitor(m) }
            if let m = mouseMoveMonitor { NSEvent.removeMonitor(m) }
            if let o = rotateObserver  { NotificationCenter.default.removeObserver(o) }
            if let o = selectAllObserver  { NotificationCenter.default.removeObserver(o) }
            if let o = cropObserver  { NotificationCenter.default.removeObserver(o) }
            if let o = saveObserver  { NotificationCenter.default.removeObserver(o) }
        }
        var lastMouseDownDocPoint: NSPoint? // 框的起点，由 mouse down 记录
        var lastMarqueeLocationInCV: NSPoint? // 判断拖动方向

        let windowTitle = WindowTitle()

        enum PanMode { case none, scroll, moveSelection }
        var panMode: PanMode = .none
        @objc func handlePan(_ g: NSPanGestureRecognizer) {
            guard let sv = scrollView, let doc = sv.documentView else { return }
            let cv = sv.contentView

            let pInCV = g.location(in: cv)
            let pDoc = cv.convert(pInCV, to: doc)
            // 1. 判断状态
            if g.state == .began {
                NSCursor.closedHand.push()
                panMode = .scroll
                if let rPx = selectionLayer.currentSelectionPx,
                   let m = makeMapper() {
                    let rDoc = m.pxToDoc(rPx)
                    if rDoc.contains(pDoc) {
                        panMode = .moveSelection
                    }
                }
                // 开启 autoScrollIfNeeded 功能
                //lastMarqueeLocationInCV = pInCV
            }
            // 2. 先处理结束，防止抬鼠标的位移
            if g.state == .ended || g.state == .cancelled {
                if panMode == .moveSelection,
                    let rPx = selectionLayer.currentSelectionPx {
                        finishSelectionPx(rPx)
                }
                panMode = .none
                NSCursor.pop()
                return
            }
            // 3. 处理位移
            let t = g.translation(in: cv)
            g.setTranslation(.zero, in: cv) // reset translation
            guard cv.bounds.contains(pInCV) else { return }
            switch panMode {
            case .moveSelection:
                //autoScrollIfNeeded(cursorInContentView: pInCV)
                //lastMarqueeLocationInCV = g.location(in: cv)
                moveSelection(by: t, cursorInDoc: pDoc)
            case .scroll:
                var o = cv.bounds.origin
                o.x -= t.x; o.y -= t.y
                o = clampOrigin(o, cv: cv, doc: doc)
                cv.scroll(to: o)
                sv.reflectScrolledClipView(cv)
            case .none:
                break
            }
        }
        
        @objc func handleZoomClick(_ g: NSClickGestureRecognizer) {
            guard let sv = scrollView, let doc = sv.documentView else { return }
            guard let path = selectionLayer.layer.path else { return }
            let pDoc = g.location(in: doc)  // overlay 坐标
            if path.contains(pDoc) {
                zoomToCurrentSelection()
            } else {
                clearSelection(updateVM: true, restoreTitle: false)
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
            var pInCV = g.location(in: cv)
            if g.state == .began || g.state == .changed {
                autoScrollIfNeeded(cursorInContentView: pInCV)
                pInCV = g.location(in: cv)
                lastMarqueeLocationInCV = pInCV
            }
            // 把手势位置从 contentView 坐标转到 documentView 坐标
            var p = cv.convert(pInCV, to: doc)
            p = restrictP(p: p)
            switch g.state {
            case .began:
                if let start = lastMouseDownDocPoint {
                    p = start // use mouse down instead
                }
                
                // [EDGE-RESIZE] 若已有选框，先做边缘命中检测；命中则进入“沿边缩放”模式
                if selectionLayer.currentSelectionPx != nil,
                   let edge = hitTestEdge(pDoc: p) {
                    beganResizingEdge(edge, on: doc)
                    return
                }
                
                if let path = selectionLayer.layer.path, path.contains(p) {
                    suppressMarquee = true
                    return
                }
                suppressMarquee = false
                //NSCursor.crosshair.push()
                selectionStartInDoc = p
                ensureSelectionLayer(on: doc)                 // 准备 overlay
                if let s = selectionStartInDoc {
                    updateSelection(from: s, to: p, fireDragging: true)
                }
            case .changed:
                // [EDGE-RESIZE] 处于沿边缩放
                if let edge = resizingEdge {
                    changedResizingEdge(edge, by: p)
                    return
                }
                
                guard !suppressMarquee, let s = selectionStartInDoc else { return }
                updateSelection(from: s, to: p, fireDragging: true)
            case .ended, .cancelled:
                // [EDGE-RESIZE] 完成沿边缩放
                if resizingEdge != nil {
                    endedResizingEdge()
                }
                if suppressMarquee {
                    // 在选框里拖动要不要放大？
                    // zoomToCurrentSelection()
                    suppressMarquee = false
                    return
                }
                NSCursor.pop()
                guard let s = selectionStartInDoc, let m = makeMapper() else { return }
                let snapped = m.snapDocRect(startDoc: s, endDoc: p)
                finishSelectionPx(snapped.rectPx)
            default:
                break
            }
        }

        func ensureSelectionLayer(on doc: NSView) {
            selectionLayer.attachIfNeeded(to: doc)
            // 双击全屏
            if cachedDoubleClickRecognizer == nil {
                let dbl = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
                dbl.numberOfClicksRequired = 2
                dbl.buttonMask = 0x1 // 左键
                doc.addGestureRecognizer(dbl)
                cachedDoubleClickRecognizer = dbl
            }
            // 单击放大选区
            if cachedClickRecognizer == nil {
                let click = NSClickGestureRecognizer(target: self, action: #selector(handleZoomClick(_:)))
                doc.addGestureRecognizer(click)
                cachedClickRecognizer = click
            }
        }

        func installMouseDownMonitor() {
            // 监听左键按下，但不“消费”事件
            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
                guard let self,
                      let sv = self.scrollView,
                      let doc = sv.documentView else { return e }
                guard sv.window?.isKeyWindow != false else { return e }

                let cv   = sv.contentView
                let pInCV = cv.convert(e.locationInWindow, from: nil)
                guard cv.bounds.contains(pInCV) else { return e }
                
                // 点击在选框外，消除选框
                if selectionLayer.layer.path != nil {
                    let docRectInCV = cv.convert(doc.bounds, from: doc)
                    if !docRectInCV.contains(pInCV) {
                        clearSelection(updateVM: true, restoreTitle: true)
                    }
                }
                
                var pDoc  = cv.convert(pInCV, to: doc)
                pDoc = self.restrictP(p: pDoc)
                self.lastMouseDownDocPoint = pDoc
                self.lastMarqueeLocationInCV = pInCV
                NSCursor.crosshair.push()

                // ✅ 新增：如果是点在“选框边缘”，说明要进入缩放；此时不要显示取色标题
                if self.selectionLayer.currentSelectionPx != nil,
                   self.hitTestEdge(pDoc: pDoc) != nil {
                    return e
                }
                // 如果点在选框内部、准备移动/缩放，你也可以选择不取色
                if let rPx = selectionLayer.currentSelectionPx,
                   let m = makeMapper() {
                    let pPx = m.docToPx(pDoc)
                    if rPx.contains(pPx) {
                        // TODO: move marquee
                        return e
                    }   // 在选框内部：不取色
                }



                guard let m = self.makeMapper() else { return e }
                let pPx = m.docToPx(pDoc)
                let px = Int(floor(pPx.x))
                let py = Int(floor(pPx.y))
                let x  = max(0, min(px, Int(self.imagePixels.width)  - 1))
                let y  = max(0, min(py, Int(self.imagePixels.height) - 1))
                
                let color = viewerVM?.colorAtPixel(x: x, y: y)
                self.windowTitle.showColor(of: sv.window,x:x, y:y, color:color)
                return e  // 不拦截事件，后续拖拽/双击照常工作
            }
            // 左键抬起：一律还原文件名
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] e in
                guard let self,
                      let sv = self.scrollView else { return e }
                self.windowTitle.restoreBase(of: sv.window)
                return e
            }
        }
    }
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        print("makeNSView")
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
        context.coordinator.viewerVM = viewerVM

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
        context.coordinator.installMouseDownMonitor()
        context.coordinator.installMouseMoveMonitor()
        return scrollView
    }
    // 每次切图/尺寸变化都会走这里：同步更新，绝不异步
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        //print("updateNSView")
        guard let hv = context.coordinator.hostingView else { return }
        hv.rootView = content
        //hv.layoutSubtreeIfNeeded()
        // The only place to update size in coordinator
        context.coordinator.imagePixels = imagePixels
        context.coordinator.baseSize = baseSize
        //context.coordinator.windowTitle.reset()
        //NOTE: 第一次打开图片，NSScrollView还没加入窗口层级，拿不到window
        if let window = nsView.window {
            if viewerVM.window !== window {
                viewerVM.window = window
            }
        }
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
func clampOrigin(_ o: NSPoint, cv: NSClipView, doc: NSView) -> NSPoint {
    var o = o
    let dw = doc.bounds.width, dh = doc.bounds.height
    let cw = cv.bounds.width, ch = cv.bounds.height
    o.x = (dw <= cw) ? (dw - cw)/2 : min(max(0, o.x), dw - cw)
    o.y = (dh <= ch) ? (dh - ch)/2 : min(max(0, o.y), dh - ch)
    return o
}





struct PixelMapper {
    let docSize: CGSize      // 实际 documentView 的大小（pt）
    let imagePixels: CGSize  // 图像像素尺寸（px）

    var contentSize: CGSize { docSize }

    var sx: CGFloat { max(0.0001, imagePixels.width  / max(0.0001, contentSize.width))  }
    var sy: CGFloat { max(0.0001, imagePixels.height / max(0.0001, contentSize.height)) }

    func docToPx(_ p: CGPoint) -> CGPoint { .init(x: p.x * sx, y: p.y * sy) }
    func pxToDoc(_ p: CGPoint) -> CGPoint { .init(x: p.x / sx, y: p.y / sy) }
    func pxToDoc(_ r: CGRect) -> CGRect { return CGRect(x: r.minX / sx, y: r.minY / sy, width: r.width / sx, height: r.height / sy) }

    // MARK: - Doc 边界
    func clampDocPoint(_ p: CGPoint) -> CGPoint {
        let w = contentSize.width, h = contentSize.height
        return .init(x: min(max(0, p.x), w),
                     y: min(max(0, p.y), h))
    }

    /// 把矩形贴齐到像素网格（floor）并夹紧到边界
    func quantizeAndClampPxRect(_ r: CGRect) -> CGRect {
        var x0 = floor(r.minX), y0 = floor(r.minY)
        var x1 = floor(r.maxX), y1 = floor(r.maxY)
        x0 = max(0, min(x0, imagePixels.width))
        y0 = max(0, min(y0, imagePixels.height))
        x1 = max(0, min(x1, imagePixels.width))
        y1 = max(0, min(y1, imagePixels.height))
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    func snapDocRect(startDoc s: CGPoint, endDoc e: CGPoint) -> (rectDoc: CGRect, rectPx: CGRect) {
        let sPx = docToPx(s), ePx = docToPx(e)
        let rawPx = CGRect(x: min(sPx.x, ePx.x),
                           y: min(sPx.y, ePx.y),
                           width: abs(ePx.x - sPx.x),
                           height: abs(ePx.y - sPx.y))
        let rPx = quantizeAndClampPxRect(rawPx)
        let rDoc = CGRect(origin: pxToDoc(rPx.origin),
                          size: .init(width: rPx.width / sx, height: rPx.height / sy))
        return (rDoc, rPx)
    }
}


extension PanMarqueeScrollView.Coordinator {
    func makeMapper() -> PixelMapper? {
        guard let sv = scrollView,
              let doc = sv.documentView
        else { return nil }

        return PixelMapper(
            docSize: doc.bounds.size,
            imagePixels: imagePixels
        )
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
    func update(rectInDoc: CGRect?) {
        guard let r = rectInDoc, r.width > 0, r.height > 0 else { layer.path = nil; return }
        let path = CGMutablePath(); path.addRect(r)
        layer.path = path
    }
    func update(snapped: (rectDoc: CGRect, rectPx: CGRect)) {
        update(rectInDoc: snapped.rectDoc)
        currentSelectionPx = snapped.rectPx
    }
    func clear() {
        layer.path = nil
        currentSelectionPx = nil
    }
}

