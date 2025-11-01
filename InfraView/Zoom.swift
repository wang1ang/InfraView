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


struct ZoomableImage: View {
    let image: NSImage
    @Binding var zoom: CGFloat
    @Binding var fitToScreen: Bool
    let fitMode: FitMode
    var onScaleChanged: (Int) -> Void
    var onLayoutChange: ((Bool, CGSize) -> Void)? = nil // (needScroll, contentSize)

    @State private var baseZoom: CGFloat = 1
    @State private var recenterMode: RecenterMode = .imageCenter
    @State private var recenterToken = UUID()
    
    private func handleWheelZoom(factor: CGFloat, mouseInWindow: NSPoint) {
        fitToScreen = false
        zoom *= factor
        recenterMode = .imageCenter
        recenterToken = UUID()
    }

    var body: some View {
        GeometryReader { proxy in
            let maxW = max(proxy.size.width, 1)
            let maxH = max(proxy.size.height, 1)

            let naturalPt = naturalPointSize(image)
            let baseW = max(naturalPt.width, 1)
            let baseH = max(naturalPt.height, 1)
            let fitScaleRaw = min(maxW / baseW, maxH / baseH)
            let effectiveFitScale = (fitMode == .fitOnlyBigToWindow) ? min(fitScaleRaw, 1) : fitScaleRaw
            let currentScale: CGFloat = fitToScreen ? effectiveFitScale : zoom

            let contentW = baseW * currentScale
            let contentH = baseH * currentScale
            
            let contentWf = floor(contentW)
            let contentHf = floor(contentH)
            
            let scale = NSApp.keyWindow?.backingScaleFactor
                ?? NSApp.keyWindow?.screen?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2.0
            let eps: CGFloat = 1.0 / scale
            let needScroll = (contentW - maxW) > eps || (contentH - maxH) > eps

            let content = ZoomedContent(width: contentWf, height:contentHf, image: image)
            
            //let contentSize = CGSize(width: contentWf, height: contentHf)
            let wheelLayer = WheelZoomCatcher(allowed: [[.option], [.command]], onZoom: handleWheelZoom)

            Group {
                if needScroll {
                    ScrollView([.horizontal, .vertical]) {
                        content
                            .background(
                                ScrollAligner(mode: recenterMode, token: recenterToken)
                            )
                    }
                    .overlay(
                        wheelLayer
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    )
                    //ScrollView([.horizontal, .vertical]) { content }
                    /*
                    CenteringScrollView(
                        contentSize: contentSize, recenterMode: recenterMode, recenterKey: recenterToken) {
                            AnyView(content)
                    }
                     */
                } else {
                    content
                        .background(wheelLayer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // 居中
                }
            }
            .onAppear { baseZoom = zoom; onScaleChanged(Int(round(currentScale * 100)));
                StatusBarStore.shared.set("Image","\(Int(baseW))×\(Int(baseH))pt")
            }
            .onChange(of: needScroll) { _, newNeed in onLayoutChange?(newNeed, CGSize(width: contentWf, height: contentHf)) }
            
            // refresh displayed scale
            .onChange(of: fitToScreen) { _, newFit in
                let cs = computeScale(isFit: newFit, baseW: baseW, baseH: baseH, maxW: maxW, maxH: maxH, zoom: zoom)
                onScaleChanged(Int(round(cs * 100)))
            }
            .onChange(of: zoom) { _, newZoom in if !fitToScreen { onScaleChanged(Int(round(newZoom * 100))) }
                baseZoom = newZoom
            }
            .onChange(of: proxy.size) { _, _ in
                if fitToScreen {
                    onScaleChanged(Int(round(currentScale * 100)))
                }
            }
            .onChange(of: fitMode) { _, _ in
                if fitToScreen {
                    onScaleChanged(Int(round(currentScale * 100)))
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { v in
                        fitToScreen = false
                        //zoom = clamp(baseZoom * v, 0.25...5)
                    }
                    .onEnded { _ in baseZoom = zoom }
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if let win = keyWindowOrFirstVisible() {
                    win.toggleFullScreen(nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .infraRecenter)) { note in
                guard let mode = note.object as? RecenterMode else { return }
                recenterMode = mode
                recenterToken = UUID() // change token
            }
        }
        .background(Color.black)
    }
}

// MARK: - Helpers

private func computeScale(isFit: Bool, baseW: CGFloat, baseH: CGFloat, maxW: CGFloat, maxH: CGFloat, zoom: CGFloat) -> CGFloat {
    let fitScale = min(maxW / baseW, maxH / baseH)
    return isFit ? fitScale : zoom
}
