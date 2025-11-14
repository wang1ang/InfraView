//
//  Marquee+Selection.swift
//  InfraView
//
//  Created by 王洋 on 13/11/2025.
//

import AppKit

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

            var pDoc = cv.convert(pCV, to: doc)
            pDoc = self.restrictP(p: pDoc)

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
