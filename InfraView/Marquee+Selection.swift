//
//  Marquee+Selection.swift
//  InfraView
//
//  Created by 王洋 on 13/11/2025.
//

import AppKit
import CoreGraphics

extension PanMarqueeScrollView.Coordinator {
    enum Edge { case left, right, top, bottom }

    /// doc 点是否靠近选框边（用 px 空间判断，避免 zoom 影响）
    func hitTestEdge(pDoc: CGPoint, tolerancePx: CGFloat = 6) -> Edge? {
        guard let rPx = selectionLayer.currentSelectionPx,
              let m = makeMapper() else { return nil }

        let pPx = m.docToPx(pDoc)

        if abs(pPx.x - rPx.minX) <= tolerancePx,
           pPx.y >= rPx.minY - tolerancePx, pPx.y <= rPx.maxY + tolerancePx {
            return .left
        }
        if abs(pPx.x - rPx.maxX) <= tolerancePx,
           pPx.y >= rPx.minY - tolerancePx, pPx.y <= rPx.maxY + tolerancePx {
            return .right
        }
        if abs(pPx.y - rPx.maxY) <= tolerancePx,
           pPx.x >= rPx.minX - tolerancePx, pPx.x <= rPx.maxX + tolerancePx {
            return .top
        }
        if abs(pPx.y - rPx.minY) <= tolerancePx,
           pPx.x >= rPx.minX - tolerancePx, pPx.x <= rPx.maxX + tolerancePx {
            return .bottom
        }
        return nil
    }

    /// 安装 mouseMove 监听：悬停到边框 → 改光标
    func installMouseMoveMonitor() {
        mouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in
            guard let self,
                  let sv = self.scrollView,
                  let doc = sv.documentView else { return e }
            guard sv.window?.isKeyWindow != false else { return e }

            let cv   = sv.contentView
            let pCV  = cv.convert(e.locationInWindow, from: nil)
            guard cv.bounds.contains(pCV) else { return e }

            // 无选框：箭头
            guard self.selectionLayer.currentSelectionPx != nil else {
                NSCursor.arrow.set()
                return e
            }

            if let edge = self.hitTestEdge(pDoc: pDoc) {
                switch edge {
                case .left, .right: NSCursor.resizeLeftRight.set()
                case .top,  .bottom: NSCursor.resizeUpDown.set()
                }
            } else {
                NSCursor.arrow.set()
            }
            return e
        }
    }
}


extension PanMarqueeScrollView.Coordinator {
    /// 从 doc 空间两点更新选框，fireDragging 为 true 时顺便更新标题
    func updateSelection(from startDoc: CGPoint,
                         to currentDoc: CGPoint,
                         fireDragging: Bool) {
        guard let m = makeMapper() else { return }
        let snapped = m.snapDocRect(startDoc: startDoc, endDoc: currentDoc)
        selectionLayer.update(snapped: snapped)
        onChanged?(snapped.rectPx)
        if fireDragging {
            showDragging(for: snapped.rectPx)
        }
    }
    func clearSelection(updateVM: Bool = true,
                        restoreTitle: Bool = true) {
        selectionLayer.clear()
        if updateVM {
            viewerVM?.updateSelection(rectPx: nil)
        }
        if restoreTitle {
            windowTitle.restoreBase(of: scrollView?.window)
        }
        selectionStartInDoc = nil
        lastMouseDownDocPoint = nil
        lastMarqueeLocationInCV = nil

    }
}

extension PanMarqueeScrollView.Coordinator {

    /// 当拖拽位置靠近/超出边缘时，自动滚动视口，并把坐标夹回安全区边缘。
    /// 使用 lastMarqueeLocationInCV 作为“上一帧位置”，只在鼠标继续朝越界方向移动时才滚动。
    func autoScrollIfNeeded(cursorInContentView p: NSPoint) {
        guard let sv = scrollView,
              let doc = sv.documentView else { return }

        let cv = sv.contentView
        let bounds = cv.bounds

        // 安全区域：只有出了这个范围才触发滚动
        let inset: CGFloat = 20
        let safeRect = bounds.insetBy(dx: inset, dy: inset)

        // 第一次：记录锚点
        guard let anchor = lastMarqueeLocationInCV else {
            return
        }

        // 在安全区内：不滚动，锚点跟着走
        if safeRect.contains(p) {
            return
        }

        // 以“上一帧位置（anchor）”作为方向参考
        let dx = p.x - anchor.x
        let dy = p.y - anchor.y

        var origin = bounds.origin

        // --- X 方向 ---
        if p.x < safeRect.minX && dx < 0 || p.x > safeRect.maxX && dx > 0{
            let acc = max(safeRect.minX - p.x, p.x - safeRect.maxX)
            origin.x += signedSqrt(dx) * (1 + acc / inset)
        }
        // --- Y 方向 ---
        if p.y < safeRect.minY && dy < 0 || p.y > safeRect.maxY && dy > 0 {
            let acc = max(safeRect.minY - p.y, p.y - safeRect.maxY)
            origin.y += signedSqrt(dy) * (1 + acc / inset)
        }
        // clamp 到合法范围
        origin = clampOrigin(origin, cv: cv, doc: doc)
        if origin != bounds.origin {
            cv.scroll(to: origin)
            sv.reflectScrolledClipView(cv) // 更新滑块位置
        }
    }
}
func signedSqrt(_ v: CGFloat) -> CGFloat {
    if v > 0 {
        return  sqrt(v)
    } else if v < 0 {
        return -sqrt(-v)
    } else {
        return 0
    }
}
