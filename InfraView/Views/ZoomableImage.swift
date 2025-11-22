//
//  ZoomableImage.swift
//  InfraView
//
//  Created by 王洋 on 12/10/2025.
//

import SwiftUI
import AppKit

/// 可缩放的图片视图
struct ZoomableImage: View {
    let image: NSImage
    @Binding var zoom: CGFloat
    let fitMode: FitMode
    let viewerVM: ViewerViewModel

    var onScaleChanged: (CGFloat) -> Void
    var onLayoutChange: ((Bool, CGSize) -> Void)? = nil
    var onViewPortChange: () -> Void

    // used only for MagnificationGesture
    @State private var baseZoom: CGFloat = 1
    @Environment(\.displayScale) private var displayScale
    
    var body: some View {
        GeometryReader { proxy in
            let px = viewerVM.processedPixelSize ?? .zero
            let naturalPt = CGSize(
                width:  px.width / displayScale,
                height: px.height / displayScale
            )
            let baseW = max(naturalPt.width, 0.1)
            let baseH = max(naturalPt.height, 0.1)

            // 核心科技：最终决定图片大小的地方！
            let currentScale: CGFloat = zoom

            let contentW = baseW * currentScale
            let contentH = baseH * currentScale

            let content = ZoomedContent(width: floor(contentW), height: floor(contentH), image: image)
            let rep = image.representations.first
            let imagePixels = CGSize(
                width: rep?.pixelsWide ?? Int(image.size.width),
                height: rep?.pixelsHigh ?? Int(image.size.height)
            )

            PanMarqueeScrollView(
                imagePixels: viewerVM.processedPixelSize ?? imagePixels,
                baseSize: CGSize(width: baseW, height: baseH),
                zoom: $zoom,
                viewerVM: viewerVM
            ) {
                content
            }
            .onAppear {
                print("onAppear:", currentScale)
                print("displayScale: \(displayScale)")
            }
            .onChange(of: zoom) { _, newZoom in
                baseZoom = newZoom
            }
            .onChange(of: proxy.size) { _, newSize in
                onViewPortChange() // 通知 view model
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { v in
                        print("set zoom in gesture")
                        zoom = clamp(baseZoom * v, 0.05...20)
                    }
                    .onEnded { _ in
                        baseZoom = zoom
                        print("magnify ended:", currentScale)
                        onScaleChanged(zoom)
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

