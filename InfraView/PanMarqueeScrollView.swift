//
//  PanMarqueeScrollView.swift
//  InfraView
//
//  Created by 王洋 on 4/11/2025.
//

import SwiftUI
import AppKit

/// 一个包装 NSScrollView 的 SwiftUI 容器
/// 仅负责 UI 层级结构（不含任何功能逻辑）
struct PanMarqueeScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    final class Coordinator {
        var scrollView: NSScrollView?
        var hostingView: NSHostingView<Content>?
        
        var selectionStartInDoc: NSPoint?
        let overlayView = NSView()
        let selectionLayer = CAShapeLayer()
        var onFinished: ((CGRect) -> Void)?
        
        @objc func handlePan(_ g: NSPanGestureRecognizer) {
            guard let scrollView = scrollView else { return }
            let contentView = scrollView.contentView

            switch g.state {
            case .began, .changed:
                // 获取拖拽位移（与上一次事件的差）
                let t = g.translation(in: contentView)
                g.setTranslation(.zero, in: contentView)

                var origin = contentView.bounds.origin
                origin.x -= t.x
                origin.y -= t.y

                // 边界夹紧
                if let doc = scrollView.documentView {
                    let maxX = max(0, doc.bounds.width  - contentView.bounds.width)
                    let maxY = max(0, doc.bounds.height - contentView.bounds.height)
                    origin.x = min(max(0, origin.x), maxX)
                    origin.y = min(max(0, origin.y), maxY)
                }

                contentView.scroll(to: origin)
                // 不需要 reflectScrolledClipView，系统会自动同步
                scrollView.reflectScrolledClipView(contentView)
            default:
                break
            }
        }
        @objc func handleOverlayClick(_ g: NSClickGestureRecognizer) {
            let p = g.location(in: overlayView)
            if let path = selectionLayer.path, !path.contains(p) {
                selectionLayer.path = nil
            }
        }
        @objc func handleMarquee(_ g: NSPanGestureRecognizer) {
            guard let sv = scrollView,
                  let doc = sv.documentView else { return }
            let cv = sv.contentView
            
            // 把手势位置从 contentView 坐标转到 documentView 坐标
            let pInContent = g.location(in: cv)
            let p = cv.convert(pInContent, to: doc)
            
            switch g.state {
            case .began:
                selectionStartInDoc = p
                ensureOverlay(on: doc)                 // 准备 overlay
                drawSelection(from: p, to: p)          // 先画一个 0 大小的框
            case .changed:
                guard let s = selectionStartInDoc else { return }
                drawSelection(from: s, to: p)
            case .ended, .cancelled:
                guard let s = selectionStartInDoc else { break }
                let r = normalizedRect(s, p)
                // 清掉
                //drawSelection(from: .zero, to: .zero)
                selectionStartInDoc = nil
                // 把结果回调给 SwiftUI（可选）
                if let vc = onFinished {
                    vc(r)
                }
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
        private func drawSelection(from a: NSPoint, to b: NSPoint) {
            let rDoc = normalizedRect(a, b)
            guard let doc = overlayView.superview else { return }
            let rOverlay = overlayView.convert(rDoc, from: doc)
            let path = CGMutablePath()
            path.addRect(rOverlay)
            selectionLayer.path = rOverlay.isEmpty ? nil : path
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
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView
        
        context.coordinator.scrollView = scrollView
        context.coordinator.hostingView = hostingView


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
