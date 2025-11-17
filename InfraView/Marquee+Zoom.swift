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
        print("zoomTo(rectPx)=\(rectPx)")
        guard rectPx.width > 1, rectPx.height > 1,
              let sv   = scrollView,
              let getZ = getZoom,
              let setZ = setZoom
        else { return }

        let cv = sv.contentView
        let cvSize = cv.bounds.size
        guard cvSize.width  > 0, cvSize.height > 0,
              baseSize.width  > 0, baseSize.height  > 0,
              imagePixels.width  > 0, imagePixels.height > 0
        else { return }

        // 用「当前 zoom 下的 rectDoc」来算放大倍数
        let oldZoom = getZ()
        guard let mapperBefore = makeMapper() else { return }

        // TODO: 加上滚动条的宽度

        let rectDocBefore = mapperBefore.pxToDoc(rectPx)
        let factorX = cvSize.width  / rectDocBefore.width
        let factorY = cvSize.height / rectDocBefore.height
        let factor  = min(factorX, factorY)
        let targetZoom = max(0.05, min(20, oldZoom * factor))

        let scale = targetZoom / oldZoom

        print("[zoomTo] oldZoom=\(oldZoom)  factorX=\(String(format: "%.3f", factorX))  factorY=\(String(format: "%.3f", factorY))  target=\(targetZoom)")

        setZ(targetZoom)

        // 下一帧再根据放大后的 doc 尺寸去滚动
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let sv  = self.scrollView
            else { return }

            sv.layoutSubtreeIfNeeded()
            //doc.layoutSubtreeIfNeeded()

            let cv       = sv.contentView
            let rectDoc = CGRect(
                x: rectDocBefore.minX * scale,
                y: rectDocBefore.minY * scale,
                width: rectDocBefore.width * scale,
                height: rectDocBefore.height * scale
            )
            
            var origin = CGPoint(x: rectDoc.minX, y: rectDoc.minY)
            let visW = sv.documentVisibleRect.width // 不算滚动条
            let visH = sv.documentVisibleRect.height
            let eps = 1.0
            if rectDoc.height + eps < rectDoc.width * visH / visW {
                let targetH = rectDoc.width * visH / visW
                origin.y -= (targetH - rectDoc.height) / 2
            } else if rectDoc.width + eps < rectDoc.height * visW / visH {
                let targetW = rectDoc.height * visW / visH
                origin.x -= (targetW - rectDoc.width) / 2
            }

            cv.scroll(to: origin)
            sv.reflectScrolledClipView(cv)

            // 缩放后重绘选框
            if let rPx = selectionLayer.currentSelectionPx, let m = makeMapper() {
                let originDoc = m.pxToDoc(rPx.origin)
                let sizeDoc   = CGSize(width: rPx.size.width / m.sx, height: rPx.size.height / m.sy)
                let rDoc      = CGRect(origin: originDoc, size: sizeDoc)
                selectionLayer.update(rectInDoc: rDoc)
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

    func handleWheel(_ e: NSEvent) {
        // 只在按住 ⌘ 时启用滚轮缩放
        guard let sv = scrollView,
              let doc = sv.documentView,
              let m = makeMapper(),
              e.hasCommand,
              e.scrollingDeltaY != 0
        else { return }
        
        let zoomIn = e.scrollingDeltaY > 0
        let cv = sv.contentView

        // 鼠标位置：window -> contentView -> doc -> px
        let mouseInCV  = cv.convert(e.locationInWindow, from: nil)
        let mouseInDoc = cv.convert(mouseInCV, to: doc)
        let mousePx    = m.docToPx(mouseInDoc)

        // 当前可视区域（doc 空间），再转成 px 空间
        let visibleDoc = cv.convert(cv.bounds, to: doc)
        let v0Px       = m.docToPx(visibleDoc.origin)
        let v1Px       = m.docToPx(CGPoint(x: visibleDoc.maxX, y: visibleDoc.maxY))

        let visWidth  = v1Px.x - v0Px.x
        let visHeight = v1Px.y - v0Px.y
        guard visWidth > 1, visHeight > 1 else { return }

        let imgW = imagePixels.width
        let imgH = imagePixels.height
        var x0: CGFloat, w: CGFloat
        var y0: CGFloat, h: CGFloat
        let targetRectPx: CGRect

        if zoomIn {
            // ---------- 放大：视口 90%，限制在「当前可见区域」内 ----------
            let scale: CGFloat = 1/1.1
            // 放大后的像素范围
            w = visWidth  * scale // (916.2 -- 10.2) * 0.9 = 833.76
            h = visHeight * scale

            if w > imgW {
                x0 = (imgW - w) / 2 // 图片居中
            } else {
                x0 = mousePx.x - w / 2 //885.7 - 833.76 / 2 = 468.8
                x0 = max(x0, v0Px.x) // max(468.8, -10.2)
                x0 = min(x0, min(v1Px.x, imgW) - w) // min(468.8, 916.2 - 833.76)
            }
            if h > imgH {
                y0 = (imgH - h) / 2 // 居中
            } else {
                y0 = mousePx.y - h / 2
                y0 = max(y0, v0Px.y)
                y0 = min(y0, min(v1Px.y, imgH) - h)
            }
        } else {
            // ---------- 缩小：视口 110%，限制在整张图片内 ----------
            let scale: CGFloat = 1.1
            w = visWidth  * scale
            h = visHeight * scale

            if w > imgW {
                x0 = (imgW - w) / 2
            } else {
                x0 = mousePx.x - w / 2
                // 一定包含目前可视区域
                x0 = min(x0, v0Px.x)
                x0 = max(x0, v1Px.x - w)
                x0 = max(x0, 0)
                x0 = min(x0, imgW - w)
            }
            if h > imgH {
                y0 = (imgH - h) / 2
            } else {
                y0 = mousePx.y - h / 2
                y0 = min(y0, v0Px.y)
                y0 = max(y0, v1Px.y - w)
                y0 = max(y0, 0)
                y0 = min(y0, imgH - h)
            }
        }
        targetRectPx = CGRect(x: x0, y: y0, width: w, height: h)

        // 丢给 zoomTo，剩下交给 zoomTo 处理
        zoomTo(rectPx: targetRectPx)
    }
    // Debug：只打 px，一位小数
    func f1(_ v: CGFloat) -> String { String(format: "%.1f", v) }
}
