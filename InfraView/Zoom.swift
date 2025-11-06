//
//  Zoom.swift
//  InfraView
//
//  Created by 王洋 on 12/10/2025.
//

import SwiftUI
import AppKit


struct ZoomableImage: View {
    let image: NSImage
    
    // core variable: zoom factor set by user
    @Binding var zoom: CGFloat
    @Binding var fitToScreen: Bool
    let fitMode: FitMode
    var onScaleChanged: (CGFloat) -> Void
    var onLayoutChange: ((Bool, CGSize) -> Void)? = nil // (needScroll, contentSize)

    @State private var baseZoom: CGFloat = 1
    
    var body: some View {
        GeometryReader { proxy in
            let maxW = max(proxy.size.width, 1)
            let maxH = max(proxy.size.height, 1)

            let naturalPt = naturalPointSize(image)
            let baseW = max(naturalPt.width, 1)
            let baseH = max(naturalPt.height, 1)
            let fitScaleRaw = min(maxW / baseW, maxH / baseH)
            let effectiveFitScale = (fitMode == .fitOnlyBigToWindow) ? min(fitScaleRaw, 1) : fitScaleRaw

            // core variable: real scale in display
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

            let rep = image.representations.first
            let imagePixels = CGSize(
                // fallback to point (image.size)
                width: rep?.pixelsWide ?? Int(image.size.width),
                height: rep?.pixelsHigh ?? Int(image.size.height)
            )

            PanMarqueeScrollView(imagePixels: imagePixels, baseSize: CGSize(width: baseW, height: baseH), zoom: $zoom) {
                content
            }
            .onAppear {
                print("onAppear:", currentScale)
                onScaleChanged(currentScale)
            }
            .onChange(of: needScroll) { _, newNeed in
                onLayoutChange?(newNeed, CGSize(width: contentWf, height: contentHf))
            }
            // refresh displayed scale
            .onChange(of: fitToScreen) { _, newFit in
                print("fitToScreen:", currentScale)
                onScaleChanged(currentScale)
            }
            .onChange(of: zoom) { _, newZoom in
                baseZoom = newZoom
                if !fitToScreen {
                    print("zoom:", currentScale)
                    onScaleChanged(currentScale)
                }
            }
            .onChange(of: proxy.size) { _, _ in
                if fitToScreen {
                    print("proxy.size:", currentScale)
                    onScaleChanged(currentScale)
                }
            }
            .onChange(of: fitMode) { _, _ in
                if fitToScreen {
                    print("fitMode:", currentScale)
                    onScaleChanged(currentScale)
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { v in
                        fitToScreen = false
                        print("set zoom in gesture")
                        zoom = clamp(baseZoom * v, 0.25...10)
                    }
                    .onEnded { _ in
                        baseZoom = zoom
                        print("magnify ended:", currentScale)
                        onScaleChanged(fitToScreen ? currentScale : zoom)
                    }
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if let win = keyWindowOrFirstVisible() {
                    win.toggleFullScreen(nil)
                }
            }
        }
        .background(Color.black)
    }
}
