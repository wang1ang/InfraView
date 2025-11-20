//
//  Marquee+Title.swift
//  InfraView
//
//  Created by 王洋 on 14/11/2025.
//

import AppKit

extension PanMarqueeScrollView.Coordinator {

    /// 把 rectPx 转成整数并显示为 Dragging Rect
    func showDraggingInTitle(for rectPx: CGRect) {
        let x = Int(rectPx.origin.x.rounded())
        let y = Int(rectPx.origin.y.rounded())
        let w = Int(rectPx.size.width.rounded())
        let h = Int(rectPx.size.height.rounded())
        windowTitle.showDraggingRect(of: scrollView?.window, x: x, y: y, w: w, h: h)
    }

    /// 把 rectPx 转成整数并显示为 Selection
    func showSelectionInTitle(for rectPx: CGRect) {
        let x = Int(rectPx.origin.x.rounded())
        let y = Int(rectPx.origin.y.rounded())
        let w = Int(rectPx.size.width.rounded())
        let h = Int(rectPx.size.height.rounded())
        windowTitle.showSelection(of: scrollView?.window, x: x, y: y, w: w, h: h)
    }
}



final class WindowTitle {
    private var base: String?

    /// 切图 / 视图更新时调用，清空缓存的 base
    func reset() {
        base = nil
    }

    private func cleanedTitle(from title: String) -> String {
        title
            .replacingOccurrences(of: #" — XY:.*$"#,
                                  with: "",
                                  options: .regularExpression)
            .replacingOccurrences(of: #" — Selection:.*$"#,
                                  with: "",
                                  options: .regularExpression)
    }

    private func ensureBase(from window: NSWindow) {
        if base == nil || base!.isEmpty {
            base = cleanedTitle(from: window.title)
        }
    }

    private func ratioText(_ w: Int, _ h: Int) -> String {
        (w > 0 && h > 0) ? String(format: "%.4f", Double(w) / Double(h)) : "-"
    }

    private func xy(_ x: Int, _ y: Int) -> String {
        "XY:(\(x),\(y))"
    }

    // MARK: - Public API（和你现在的调用保持一致）

    func restoreBase(of window: NSWindow?) {
        guard let win = window else { return }
        ensureBase(from: win)
        win.title = base ?? win.title
    }

    func showDraggingRect(of window: NSWindow?, x: Int, y: Int, w: Int, h: Int) {
        guard let win = window else { return }
        if w > 0 && h > 0 {
            let ratio = ratioText(w, h)
            win.title = "\(xy(x, y))(\(w)x\(h) pixels, \(ratio))"
        } else {
            win.title = xy(x, y)
        }
    }

    func showSelection(of window: NSWindow?, x: Int, y: Int, w: Int, h: Int) {
        guard let win = window else { return }
        ensureBase(from: win)
        guard let base = base else { return }

        if w > 0 && h > 0 {
            let ratio = ratioText(w, h)
            win.title = "\(base) — Selection: \(x), \(y); \(w) x \(h); \(ratio)"
        } else {
            win.title = base
        }
    }

    func showColor(of window: NSWindow?, x: Int, y: Int, color: NSColor?) {
        guard let win = window else { return }
        ensureBase(from: win)

        if let c = color?.usingColorSpace(.sRGB) {
            let r = Int(round(c.redComponent   * 255))
            let g = Int(round(c.greenComponent * 255))
            let b = Int(round(c.blueComponent  * 255))
            let a = Int(round(c.alphaComponent * 255))
            let html = String(format: "#%02X%02X%02X", r, g, b)
            win.title = "XY:(\(x),\(y)) - RGB:(\(r),\(g),\(b),a:\(a)), HTML:(\(html))"
        } else {
            win.title = xy(x, y)
        }
    }
}

