//
//  Zoom.swift
//  InfraView
//
//  Created by 王洋 on 12/10/2025.
//

import SwiftUI
import AppKit

struct WheelZoomCatcher: NSViewRepresentable {
    /// 允许触发缩放的一组修饰键组合（任一组合满足即可）
    var allowed: [NSEvent.ModifierFlags] = [[.option], [.command]]
    var onZoom: (_ factor: CGFloat, _ mouseInWindow: NSPoint) -> Void

    final class V: NSView {
        var allowed: [NSEvent.ModifierFlags] = []
        var onZoom: ((CGFloat, NSPoint) -> Void)!
        var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                    guard let self, let win = self.window, e.window === win else { return e }
                    let p = self.convert(e.locationInWindow, from: nil)
                    guard self.bounds.contains(p) else { return e }

                    // 任一组合满足即可（例如按住 ⌥ 或 ⌘）
                    let hit = self.allowed.contains { combo in
                        e.modifierFlags.intersection(combo) == combo
                    }
                    if hit {
                        let dy = e.scrollingDeltaY
                        //print("dy=\(dy), precise=\(e.hasPreciseScrollingDeltas)")
                        let factor = dy > 0 ? 1.1 : 1.0 / 1.1
                        self.onZoom(factor, e.locationInWindow)
                        return nil
                    }
                    return e
                }
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }

    func makeNSView(context: Context) -> V {
        let v = V()
        v.allowed = allowed
        v.onZoom  = onZoom
        return v
    }
    func updateNSView(_ v: V, context: Context) {
        v.allowed = allowed
        v.onZoom  = onZoom
    }
}
