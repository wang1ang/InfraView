//
//  Viewer.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import SwiftUI
import AppKit

/// 图片查看器视图
@MainActor
struct Viewer: View {
    @ObservedObject var store: ImageStore
    @ObservedObject var viewerVM: ViewerViewModel
    @EnvironmentObject private var bar: StatusBarStore
    @ObservedObject private var sharedBar = StatusBarStore.shared
    let fitMode: FitMode

    var body: some View {
        Group {
            if let index = store.selection, index < store.imageURLs.count {
                let url = store.imageURLs[index]
                
                ZStack {
                    if let err = viewerVM.loadingError {
                        Placeholder(title: "Failed to load", systemName: "exclamationmark.triangle", text: err)
                    } else if let img = viewerVM.processedImage {
                        ZoomableImage(
                            image: img,
                            zoom: Binding(
                                get: { viewerVM.zoom },
                                set: { v in
                                    viewerVM.drive(reason: .zoom(v), mode: fitMode)
                                }
                            ),
                            fitMode: fitMode,
                            viewerVM: viewerVM,
                            onScaleChanged: { newZoom in
                                viewerVM.zoom = newZoom
                                bar.setZoom(percent: Int(round(newZoom * 100)))
                            },
                            onLayoutChange: nil,
                            onViewPortChange: {
                                viewerVM.fitImageToWindow()
                                bar.setZoom(percent: Int(round(viewerVM.zoom * 100)))
                            }
                        )
                        .id(url)
                        .navigationTitle(url.lastPathComponent)
                        .onAppear() {
                            bar.updateStatus(url: url, image: img, index: index, total: store.imageURLs.count)
                            bar.setZoom(percent: Int(round(viewerVM.zoom * 100)))
                        }
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(1.2)
                            Text("Loading...")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onChange(of: viewerVM.processedImage) { _, newImg in
                    if let newImg {
                        bar.updateStatus(url: url, image: newImg, index: index, total: store.imageURLs.count)
                        bar.setZoom(percent: Int(round(viewerVM.zoom * 100)))
                    }
                }
                .onAppear(perform: showCurrent)
                .onChange(of: store.selection) { _, _ in showCurrent() }
                .onChange(of: fitMode) { _, _ in
                    guard let idx = store.selection,
                          idx < store.imageURLs.count
                    else { return }
                    viewerVM.drive(reason: .fitToggle, mode: fitMode)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                    showCurrent()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                    showCurrent()
                }
            } else {
                Placeholder(title: "No Selection", systemName: "rectangle.dashed", text: "Open an image (⌘O)")
            }
        }
        .onChange(of: sharedBar.isVisible) { _, _ in
            viewerVM.drive(reason: .layout, mode: fitMode)
        }
        .onChange(of: viewerVM.zoom) { _, newZoom in
            bar.setZoom(percent: Int(round(newZoom * 100)))
        }
        .onReceive(NotificationCenter.default.publisher(for: .infraToggleStar)) { _ in
            if viewerVM.window?.isKeyWindow == true {
                bar.toggleStar()
            }
        }
    }

    private func showCurrent() {
        guard let idx = store.selection,
              idx < store.imageURLs.count
        else { return }
        viewerVM.show(index: idx, in: store.imageURLs, fitMode: fitMode)
    }
}

/// 占位符视图
struct Placeholder: View {
    let title: String
    let systemName: String
    let text: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 48))
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

