//
//  Marquee+Resize.swift
//  InfraView
//
//  Created by 王洋 on 13/11/2025.
//

import SwiftUI
import AppKit

extension PanMarqueeScrollView.Coordinator {
    /// 将 px 矩形提交到 overlay（统一在这里 snap）
    func commitSelectionPx(_ rPx: CGRect) -> CGRect? {
        guard let m = makeMapper() else { return nil }
        let snapped = m.quantizeAndClampPxRect(rPx)                     // ← 量化
        let rDoc = CGRect(origin: m.pxToDoc(snapped.origin),
                          size:   CGSize(width: snapped.width / m.sx,
                                         height: snapped.height / m.sy))
        selectionLayer.update(rectInDoc: rDoc)
        selectionLayer.currentSelectionPx = snapped
        onChanged?(snapped)
        return snapped
    }
    
    func finishSelectionPx(_ rPx: CGRect) {
        guard let snapped = commitSelectionPx(rPx) else { return }
        onFinished?(snapped)
        viewerVM?.updateSelection(rectPx: snapped)
        showSelection(for: snapped)
        selectionStartInDoc = nil
        lastMouseDownDocPoint = nil
        lastMarqueeLocationInCV = nil
    }
    
    func beganResizingEdge(_ edge: Edge, on doc: NSView) {
        resizingEdge = edge
        ensureSelectionLayer(on: doc)
        // 显示当前选框状态
        
        if let rPx = selectionLayer.currentSelectionPx {
            showDragging(for: rPx)
        }
    }
    
    func changedResizingEdge(_ edge: Edge, by p: CGPoint) {
        guard var rPx = selectionLayer.currentSelectionPx,
              let m = makeMapper() else { return }

        let pPx = m.docToPx(p)

        // 先缓存旧边界，后续计算只用这些常量，避免 maxX/minX 动态变化带来的连锁反应
        let oldLeft   = rPx.minX
        let oldRight  = rPx.maxX
        let oldBottom = rPx.minY
        let oldTop    = rPx.maxY

        switch edge {
        case .left:
            let newLeft = pPx.x
            if newLeft <= oldRight {
                // 正常情况：还在右边界左侧
                rPx.origin.x = newLeft
                rPx.size.width = max(0, oldRight - newLeft)
            } else {
                // ✅ 交叉：左边拖到右边右侧
                // 把矩形翻转为以 oldRight 为左边，以 newLeft 为右边
                rPx.origin.x = oldRight
                rPx.size.width = newLeft - oldRight
                // 将拖动边切换为 .right，后续继续顺滑拖动
                resizingEdge = .right
            }

        case .right:
            let newRight = pPx.x
            if newRight >= oldLeft {
                rPx.origin.x = oldLeft
                rPx.size.width = max(0, newRight - oldLeft)
            } else {
                // ✅ 交叉：右边拖到左边左侧
                rPx.origin.x = newRight
                rPx.size.width = oldLeft - newRight
                resizingEdge = .left
            }

        case .bottom:
            let newBottom = pPx.y
            if newBottom <= oldTop {
                rPx.origin.y = newBottom
                rPx.size.height = max(0, oldTop - newBottom)
            } else {
                // ✅ 交叉：下边拖到上边上侧
                rPx.origin.y = oldTop
                rPx.size.height = newBottom - oldTop
                resizingEdge = .top
            }

        case .top:
            let newTop = pPx.y
            if newTop >= oldBottom {
                rPx.origin.y = oldBottom
                rPx.size.height = max(0, newTop - oldBottom)
            } else {
                // ✅ 交叉：上边拖到下边下侧
                rPx.origin.y = newTop
                rPx.size.height = oldBottom - newTop
                resizingEdge = .bottom
            }
        }
        guard let snapped = commitSelectionPx(rPx) else { return }
        // 拖动中显示“Dragging Rect”
        showDragging(for: snapped)
    }

    func endedResizingEdge() {
        if let rPx = selectionLayer.currentSelectionPx {
            finishSelectionPx(rPx)        // ← 关键：结束时显示“Selection …”
        }
        resizingEdge = nil
        lastMouseDownDocPoint = nil
    }
}

extension PanMarqueeScrollView.Coordinator {
    @MainActor
    func handleSelectAll() {
        // 只响应当前这个 window 是 key 的情况
        guard let sv = scrollView,
              let doc = sv.documentView,
              sv.window?.isKeyWindow == true
        else { return }

        // 整张图的像素选区
        let rectPx = CGRect(
            x: 0,
            y: 0,
            width: imagePixels.width,
            height: imagePixels.height
        )
        ensureSelectionLayer(on: doc)
        finishSelectionPx(rectPx)
    }
}
