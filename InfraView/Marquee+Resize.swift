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
    func drawSelectionOverlay(_ rPx: CGRect) -> CGRect? {
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
        guard let snapped = drawSelectionOverlay(rPx) else { return }
        onFinished?(snapped)
        viewerVM?.updateSelection(rectPx: snapped)
        showSelectionInTitle(for: snapped)
        selectionStartInDoc = nil
        lastMouseDownDocPoint = nil
        lastMarqueeLocationInCV = nil
    }

    func beganResizingEdge(_ edge: Edge, on doc: NSView) {
        resizingEdge = edge
        ensureSelectionLayer(on: doc)
        // 显示当前选框状态
        
        if let rPx = selectionLayer.currentSelectionPx {
            showDraggingInTitle(for: rPx)
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
        guard let snapped = drawSelectionOverlay(rPx) else { return }
        // 拖动中显示“Dragging Rect”
        showDraggingInTitle(for: snapped)
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
    /// 仅在拖动过程中更新选框（不 quantize、不 clamp 到像素）
    /// rPx 是“连续坐标”，只拿来画 UI 和更新 VM
    func updateSelectionWhileDragging(_ rPx: CGRect) {
        guard let m = makeMapper() else { return }
        let rDoc = CGRect(
            origin: m.pxToDoc(rPx.origin),
            size: CGSize(width: rPx.width / m.sx,
                         height: rPx.height / m.sy)
        )
        selectionLayer.update(rectInDoc: rDoc)
        selectionLayer.currentSelectionPx = rPx
        onChanged?(rPx)
        showDraggingInTitle(for: rPx)
    }
    /// 根据 contentView 内的 translation 移动选框（px 空间 + clamp）
    func moveSelection(by translationInCV: CGPoint, cursorInDoc pDoc: CGPoint) {
        guard translationInCV != .zero,
              var rPx = selectionLayer.currentSelectionPx,
              let m = makeMapper()
        else { return }

        // contentView 的 dx/dy 和 doc 的 dx/dy 是同一个坐标系（当前实现）
        let deltaPx = CGPoint(x: translationInCV.x * m.sx,
                              y: translationInCV.y * m.sy)
        rPx.origin.x += deltaPx.x
        rPx.origin.y += deltaPx.y

        // 鼠标一定在选框内
        let pPx = m.docToPx(pDoc)
        if pPx.x < rPx.minX {
            rPx.origin.x = pPx.x
        } else if pPx.x > rPx.maxX {
            rPx.origin.x = pPx.x - rPx.width
        }
        if pPx.y < rPx.minY {
            rPx.origin.y = pPx.y
        } else if pPx.y > rPx.maxY {
            rPx.origin.y = pPx.y - rPx.height
        }

        // 允许的原点范围：[0, imagePixels - rectSize]
        let maxX = imagePixels.width  - rPx.width
        let maxY = imagePixels.height - rPx.height
        rPx.origin.x = min(max(0, rPx.origin.x), maxX)
        rPx.origin.y = min(max(0, rPx.origin.y), maxY)

        updateSelectionWhileDragging(rPx)
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
