//
//  Marquee+Zoom.swift
//  InfraView
//
//  Created by 王洋 on 15/11/2025.
//
import AppKit
extension PanMarqueeScrollView.Coordinator {
    /// 把像素坐标下的 rect 放大到视口（尽量铺满并居中）
    @MainActor
    func zoomTo(rectPx: CGRect) {
        guard rectPx.width > 1, rectPx.height > 1,
              let sv   = scrollView,
              let setZ = setZoom
        else { return }

        let cv = sv.contentView
        let viewSize = cv.bounds.size
        guard viewSize.width  > 0, viewSize.height > 0,
              baseSize.width  > 0, baseSize.height  > 0,
              imagePixels.width  > 0, imagePixels.height > 0
        else { return }

        // 1. 计算 zoom（让 rect 正好塞进视口，不留 padding）
        let zx = (viewSize.width  * imagePixels.width)  / (rectPx.width  * baseSize.width)
        let zy = (viewSize.height * imagePixels.height) / (rectPx.height * baseSize.height)
        var targetZoom = min(zx, zy)
        targetZoom = min(20, max(0.05, targetZoom))

        setZ(targetZoom)

        // 2. 下一帧：根据放大后的 doc 尺寸滚动 + 重绘选框
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let sv  = self.scrollView,
                  let doc = sv.documentView,
                  let m   = self.makeMapper()
            else { return }

            sv.layoutSubtreeIfNeeded()

            let cv       = sv.contentView
            let viewSize = cv.bounds.size
            let rectDoc  = m.pxToDoc(rectPx)

            // 让 rect 的中心落在视口中心
            var origin = NSPoint(
                x: rectDoc.midX - viewSize.width  / 2,
                y: rectDoc.midY - viewSize.height / 2
            )
            origin = clampOrigin(origin, cv: cv, doc: doc)

            cv.scroll(to: origin)
            sv.reflectScrolledClipView(cv)

            // 如果当前有选框：按像素选区重算一遍 overlay（保持和图片对齐）
            if let rPx = self.selectionLayer.currentSelectionPx {
                let originDoc = m.pxToDoc(rPx.origin)
                let sizeDoc   = CGSize(width: rPx.size.width / m.sx,
                                       height: rPx.size.height / m.sy)
                let rDoc      = CGRect(origin: originDoc, size: sizeDoc)
                self.selectionLayer.update(rectInDoc: rDoc)
            }
        }
    }

    /// 便捷：对当前选框 zoom-to-fit
    @MainActor
    func zoomToCurrentSelection() {
        guard let rPx = selectionLayer.currentSelectionPx else { return }
        zoomTo(rectPx: rPx)
        
        clearSelection(updateVM: true, restoreTitle: true)
    }
}
