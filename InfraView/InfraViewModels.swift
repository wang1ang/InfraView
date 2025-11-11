// InfraViewModels.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine


@MainActor
final class ViewerViewModel: ObservableObject {
    // 状态
    @Published var zoom: CGFloat = 1
    @Published var imageAutoFit = false
    @Published var processedImage: NSImage?
    @Published var loadingError: String?
    @Published var selectionRectPx: CGRect?
    
    public var window: NSWindow?

    private var baseImage: NSImage?
    private var currentURL: URL?
    private var currentFitMode: FitMode = .fitOnlyBigToWindow
    
    // 依赖注入
    private let repo: ImageRepository // 磁盘加载
    private let cache: ImageCache // 内存缓存
    private let preloader: ImagePreloader // 预加载前后图片
    private let sizer: WindowSizer // 计算窗口尺寸和fit缩放比

    init(repo: ImageRepository, cache: ImageCache, preloader: ImagePreloader, sizer: WindowSizer) {
        self.repo = repo; self.cache = cache; self.preloader = preloader; self.sizer = sizer
    }

    // 统一驱动：新图 / 切换 Fit / 改 Zoom 都走这里
    // 给出两个东西：
    // 1. 要不要fit
    // 2. 决定窗口尺寸
    enum Reason: Equatable { case newImage, fitToggle, zoom(CGFloat) }
    func drive(reason: Reason, mode: FitMode, window: NSWindow) {
        if reason == .newImage || reason == .fitToggle {
            currentFitMode = mode
        }
        // 没有 processedImage 直接返回
        guard let img = processedImage else { return }

        switch reason {
        case .newImage:
            // restore zoom
            zoom = 1
            if mode == .fitOnlyBigToDesktop && sizer.isBigOnDesktop(img, window: window) {
                // pre-set zoom for resizing window
                zoom = sizer.desktopFitScale(for: img, in: window)
            }
            
            // 初始状态
            switch currentFitMode {
            case .doNotFit:           imageAutoFit = false
            case .fitWindowToImage:   imageAutoFit = false
            case .fitImageToWindow:   imageAutoFit = true
            case .fitOnlyBigToWindow: imageAutoFit = true
            case .fitOnlyBigToDesktop:imageAutoFit = false
            }
        // TODO: remove fitToggle
        case .fitToggle:
            switch currentFitMode {
            case .doNotFit:           imageAutoFit = false
            case .fitWindowToImage:   imageAutoFit = false
            case .fitImageToWindow:   imageAutoFit = true
            case .fitOnlyBigToWindow: imageAutoFit = true
            case .fitOnlyBigToDesktop:imageAutoFit = false
            }
            if mode == .fitOnlyBigToDesktop && sizer.isBigOnDesktop(img, window: window) {
                // pre-set zoom for resizing window
                zoom = sizer.desktopFitScale(for: img, in: window)
            }
            if mode == .doNotFit {
                zoom = 1
            }

        case .zoom(let v):
            imageAutoFit = false
            zoom = v
        }
        print(reason, currentFitMode, zoom)
        // 统一计算目标内容尺寸并调窗口
        let targetSize = desiredContentSize(for: img, mode: currentFitMode, window: window)
        print("targetSize:", targetSize)
        
        var shouldResizeWindow = currentFitMode == .fitWindowToImage || currentFitMode == .fitOnlyBigToDesktop
        
        if (currentFitMode == .fitImageToWindow || currentFitMode == .fitOnlyBigToWindow), reason != .newImage {
            shouldResizeWindow = false
        }
        if currentFitMode == .fitWindowToImage, case .zoom = reason {
            shouldResizeWindow = true
        }
        if currentFitMode == .fitImageToWindow, case .zoom = reason {
            shouldResizeWindow = false
            print("freeze window")
        }
        if shouldResizeWindow {
            print("resizeWindow")
            sizer.resizeWindow(toContent: targetSize, mode: currentFitMode)
        }
        fitImageToWindow(window: window)
    }
    func fitImageToWindow(window: NSWindow) {
        guard let img = processedImage else { return }
        if !imageAutoFit { return }
        print("fit to screen")
        let naturalPt = naturalPointSize(img)
        let baseW = max(naturalPt.width, 1)
        let baseH = max(naturalPt.height, 1)
        let targetSize = window.contentLayoutRect.size   // 当前窗口内容区（考虑了工具栏等）
        //let targetSize = sizer.fittedContentSize(for: img, in: window)
        let statusbar = StatusBarStore.shared.height

        let scaleX = targetSize.width / baseW
        let scaleY = (targetSize.height - statusbar) / baseH
        let newScale = min(scaleX, scaleY)
        if currentFitMode == .fitOnlyBigToWindow && newScale > 1 { zoom = 1 }
        else {
            zoom = min(scaleX, scaleY)
        }
    }
    
    // 载入/切图：只负责拿图，其余交给 drive(.newImage)
    func show(index: Int, in urls: [URL], fitMode: FitMode, window: NSWindow) {
        currentFitMode = fitMode
        guard urls.indices.contains(index) else { return }
        let url = urls[index]
        currentURL = url  // used for persistent rotate
        loadingError = nil
        processedImage = nil   // 清空旧图，避免误用

        // 1) 先用缓存（同步路径）
        if let cached = cache.get(url) {
            baseImage = cached
            let q = RotationStore.shared.get(for: url)
            processedImage = (q == 0) ? cached : rotate(cached, quarterTurns: q)
            drive(reason: .newImage, mode: fitMode, window: window)
        } else {
            // 2) 没缓存：异步加载，回主线程后再应用旋转并 drive
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let result = try? self.repo.load(at: url)
                await MainActor.run {
                    // 若期间用户已切到别的图，避免回写
                    guard self.currentURL == url else { return }
                    if let (img, _) = result {
                        self.baseImage = img
                        self.cache.set(url, img)
                        let q = RotationStore.shared.get(for: url)
                        self.processedImage = (q == 0) ? img : rotate(img, quarterTurns: q)
                        self.drive(reason: .newImage, mode: fitMode, window: window)
                    } else {
                        self.loadingError = "Unsupported image format."
                    }
                }
            }
        }
        preloader.preload(adjacentOf: index, in: urls)
    }

    // 统一把“要多大”和“是否滚动条感知”算出来
    private func desiredContentSize(for img: NSImage, mode: FitMode, window: NSWindow) -> CGSize {
        // targetSize
        switch mode {
        case .fitImageToWindow:
            return sizer.fittedContentSize(for: img, in: window)

        case .fitOnlyBigToWindow:
            if isBigInCurrentWindow(img, window: window) {
                return sizer.fittedContentSize(for: img, in: window)
            } else {
                // 小图 → 用 1x 大小（带屏幕上限）
                return scaledContentSize(for: img, scale: 1)
            }
        case .fitOnlyBigToDesktop:
            let sz = alignedScaledSizeToBacking(img, scale: zoom, window: window)
            return sz
        case .fitWindowToImage:
            // 不启用 fit，按当前 zoom（初始 1x）并限幅到屏幕
            //let sz = alignedScaledSizeToBacking(img, scale: zoom, window: window)
            //return sz
            return scaledContentSize(for: img, scale: zoom)

        case .doNotFit:
            // 同上，但明确不自动调整：也给窗口一个合理大小（你也可以改为保持窗口不变）
            return scaledContentSize(for: img, scale: zoom)
        }
    }
    private func isBigInCurrentWindow(_ img: NSImage, window: NSWindow) -> Bool {
        let natural = naturalPointSize(img)
        let layout = window.contentLayoutRect.size   // 当前窗口内容区（考虑了工具栏等）
        return natural.width > layout.width || natural.height > layout.height
    }
    private func alignedScaledSizeToBacking(_ img: NSImage, scale: CGFloat, window: NSWindow) -> CGSize {
        let base = naturalPointSize(img)
        let w = base.width  * scale
        let h = base.height * scale
        let s = window.backingScaleFactor
        // ZoomableImage 用的是 floor，所以这里也用 floor，避免窗口比内容“略大”
        return CGSize(width: floor(w * s) / s,
                      height: floor(h * s) / s)
    }
    
    func rotateCurrentImage(fitMode: FitMode, by q: Int, window: NSWindow) {
        guard let url = currentURL, let base = baseImage else { return }
        
        let oldQ = RotationStore.shared.get(for: url)
        let newQ = ((oldQ + q) % 4 + 4) % 4
        RotationStore.shared.set(newQ, for: url)
        
        processedImage = (newQ == 0) ? base : rotate(base, quarterTurns: newQ)
        
        drive(reason: .fitToggle, mode: fitMode, window: window)
        //onScaleChanged?(Int(round(zoom * 100)))
    }
    
    func updateSelection(rectPx: CGRect?) {
        selectionRectPx = rectPx
    }
    // ✅ 复制当前选区到剪贴板（如果有选区且有图像）
    func copySelectionToPasteboard() {
        guard
            let img = processedImage,
            let rectPx = selectionRectPx,
            rectPx.width > 0, rectPx.height > 0
        else { return }

        // 从 NSImage 拿 CGImage
        var proposedRect = CGRect(origin: .zero, size: img.size)
        guard let cg = img.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return
        }

        guard let cropped = cg.cropping(to: rectPx) else { return }

        let subImage = NSImage(cgImage: cropped, size: .zero)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([subImage])
    }
    public func colorAtPixel(x: Int, y: Int) -> NSColor? {
        guard let image = processedImage else { return nil }
        // 把 NSImage 转成 CGImage
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }

        // 用 CGImage 创建一个 bitmap rep
        let rep = NSBitmapImageRep(cgImage: cg)

        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0, h > 0 else { return nil }

        let cx = min(max(0, x), w - 1)
        let cy = min(max(0, y), h - 1)      // 如果发现上下颠倒，再改成 h - 1 - …

        return rep.colorAt(x: cx, y: cy)
    }

}
