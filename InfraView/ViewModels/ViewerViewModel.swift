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
    @Published var renderedImage: NSImage?
    @Published var loadingError: String?
    @Published var selectionRectPx: CGRect?
    
    // 撤销栈
    var committedCGImage: CGImage?        // 当前图
    var undoStack: [CGImage] = []         // 撤销栈
    var redoStack: [CGImage] = []         // 重做栈
    let maxHistory = 5                    // 最多保留多少步

    
    public var window: NSWindow?
    func setWindow(_ win: NSWindow?) {
        if self.window !== win {
            window = win
        }
    }

    private var baseImage: LoadedImage?
    
    @Published public var renderedPixelSize: CGSize?
    public var currentURL: URL?
    public var currentFitMode: FitMode = .fitOnlyBigToWindow
    
    // 依赖注入
    private let repo: ImageRepository // 磁盘加载
    private let cache: ImageCache // 内存缓存
    private let preloader: ImagePreloader // 预加载前后图片
    private let sizer: WindowSizer // 计算窗口尺寸和fit缩放比
    
    let bar = StatusBarStore()

    init(repo: ImageRepository, cache: ImageCache, preloader: ImagePreloader, sizer: WindowSizer) {
        self.repo = repo; self.cache = cache; self.preloader = preloader; self.sizer = sizer
    }

    // 统一驱动：新图 / 切换 Fit / 改 Zoom 都走这里
    // 给出两个东西：
    // 1. 要不要fit
    // 2. 决定窗口尺寸
    enum Reason: Equatable { case newImage, fitToggle, layout, zoom(CGFloat) }
    func defaultAutoFit(fitMode: FitMode) -> Bool {
        switch currentFitMode {
        case .doNotFit:            return false
        case .fitWindowToImage:    return false
        case .fitImageToWindow:    return true
        case .fitOnlyBigToWindow:  return true
        case .fitOnlyBigToDesktop: return false
        }
    }
    func drive(reason: Reason, mode: FitMode) {
        guard let window = self.window ?? keyWindowOrFirstVisible() else { return }
        if reason == .newImage || reason == .fitToggle {
            currentFitMode = mode
        }
        // 没有 renderßedImage 直接返回
        guard let img = renderedImage else { return }
        let basePt = naturalPoint()

        imageAutoFit = defaultAutoFit(fitMode: currentFitMode)
        switch reason {
        case .newImage:
            // restore zoom
            zoom = 1
            if mode == .fitOnlyBigToDesktop && sizer.isBigOnDesktop(basePt, window: window) {
                // pre-set zoom for resizing window
                zoom = sizer.desktopFitScale(for: basePt, in: window)
            }
        case .fitToggle:
            if mode == .fitOnlyBigToDesktop && sizer.isBigOnDesktop(basePt, window: window) {
                // pre-set zoom for resizing window
                zoom = sizer.desktopFitScale(for: basePt, in: window)
            }
            if mode == .doNotFit || mode == .fitWindowToImage {
                zoom = 1
            }
        case .zoom(let v):
            zoom = v
            imageAutoFit = false
        case .layout:
            // layout change (e.g. status bar):
            //   keep the zoom
            if mode == .fitOnlyBigToDesktop && sizer.isBigOnDesktop(basePt, window: window) {
                zoom = sizer.desktopFitScale(for: basePt, in: window)
            }
            break
        }
        print("drive:", reason, currentFitMode, zoom, imageAutoFit)
        // 统一计算目标内容尺寸并调窗口
        let targetSize = desiredContentSize(for: basePt, mode: currentFitMode, window: window)
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
            sizer.resizeWindow(toContent: targetSize, mode: currentFitMode)
        }
        fitImageToWindow()
    }
    func getFactor() -> CGFloat {
        guard let window = self.window ?? keyWindowOrFirstVisible() else { return 1.0}
        return window.backingScaleFactor
    }
    func naturalPoint() -> CGSize {
        let factor = getFactor()
        return CGSize(width: (renderedPixelSize?.width ?? 0) / factor, height: (renderedPixelSize?.height ?? 0) / factor)
    }
    func fitImageToWindow() {
        guard let window = self.window ?? keyWindowOrFirstVisible() else { return }
        guard let img = renderedImage else { return }
        if !imageAutoFit { return }
        print("fit to screen")
        let basePt = naturalPoint()
        let baseW = max(basePt.width, 1)
        let baseH = max(basePt.height, 1)
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
    func show(index: Int, in urls: [URL], fitMode: FitMode) {
        print("show")
        currentFitMode = fitMode
        guard urls.indices.contains(index) else { return }
        let url = urls[index]
        currentURL = url  // used for persistent rotate
        loadingError = nil
        setRenderedImage(nil) // 清空旧图，避免误用

        // 1) 先用缓存（同步路径）
        if let cached = cache.get(url) {
            baseImage = cached
            renderedPixelSize = cached.pixelSize
            let q = RotationStore.shared.get(for: url)
            let final = (q == 0) ? cached : rotate(cached, quarterTurns: q)
            setRenderedImage(final)
            resetHistoryForNewImage(from: final.image)
            drive(reason: .newImage, mode: fitMode)
        } else {
            // 2) 没缓存：异步加载，回主线程后再应用旋转并 drive
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let result = try? self.repo.load(at: url)
                await MainActor.run {
                    // 若期间用户已切到别的图，避免回写
                    guard self.currentURL == url else { return }
                    if let (cg, px) = result {
                        let img = LoadedImage(
                            image: NSImage(cgImage: cg, size: .zero),
                            pixelSize: px)
                        self.baseImage = img
                        self.renderedPixelSize = px
                        self.cache.set(url, img)
                        let q = RotationStore.shared.get(for: url)
                        let final = (q == 0) ? img : rotate(img, quarterTurns: q)
                        self.setRenderedImage(final)
                        self.resetHistoryForNewImage(from: final.image)
                        self.drive(reason: .newImage, mode: fitMode)
                    } else {
                        self.loadingError = "Unsupported image format."
                    }
                }
            }
        }
        preloader.preload(adjacentOf: index, in: urls)
    }

    // 统一把“要多大”和“是否滚动条感知”算出来
    private func desiredContentSize(for basePt: CGSize, mode: FitMode, window: NSWindow) -> CGSize {
        switch mode {
        case .fitImageToWindow:
            return sizer.fittedContentSize(for: basePt, in: window)

        case .fitOnlyBigToWindow:
            if isBigInCurrentWindow(for: basePt, window: window) {
                return sizer.fittedContentSize(for: basePt, in: window)
            } else {
                // 小图 → 用 1x 大小（带屏幕上限）
                return scaledContentSize(for: basePt, scale: 1, window: window)
            }
        case .fitOnlyBigToDesktop:
            let sz = alignedScaledSizeToBacking(for: basePt, scale: zoom, window: window)
            return sz
        case .fitWindowToImage:
            // 不启用 fit，按当前 zoom（初始 1x）并限幅到屏幕
            //let sz = alignedScaledSizeToBacking(img, scale: zoom, window: window)
            //return sz
            return scaledContentSize(for: basePt, scale: zoom, window: window)

        case .doNotFit:
            // 同上，但明确不自动调整：也给窗口一个合理大小（你也可以改为保持窗口不变）
            return scaledContentSize(for: basePt, scale: zoom, window: window)
        }
    }
    private func isBigInCurrentWindow(for basePt: CGSize, window: NSWindow) -> Bool {
        let layout = window.contentLayoutRect.size   // 当前窗口内容区（考虑了工具栏等）
        return basePt.width > layout.width || basePt.height > layout.height
    }
    private func alignedScaledSizeToBacking(for basePt: CGSize, scale: CGFloat, window: NSWindow) -> CGSize {
        let w = basePt.width  * scale
        let h = basePt.height * scale
        let s = window.backingScaleFactor
        // ZoomableImage 用的是 floor，所以这里也用 floor，避免窗口比内容“略大”
        return CGSize(width: floor(w * s) / s,
                      height: floor(h * s) / s)
    }
    
    func rotateCurrentImage(fitMode: FitMode, by q: Int) {
        guard let url = currentURL, let base = baseImage else { return }
        
        let oldQ = RotationStore.shared.get(for: url)
        let newQ = ((oldQ + q) % 4 + 4) % 4
        RotationStore.shared.set(newQ, for: url)
        
        let rotated = (newQ == 0) ? base : rotate(base, quarterTurns: newQ)
        // 旋转不参与Undo,不用applyCGImage
        setRenderedImage(rotated)
        // 旋转不参与Undo
        resetHistoryForNewImage(from: rotated.image)
        
        drive(reason: .fitToggle, mode: fitMode)
    }
    
    func flipCurrentImage(by direction: String) {
        guard let image = renderedImage,
              let pixelSize = renderedPixelSize else { return }
        let currentImage = LoadedImage(image: image, pixelSize: pixelSize)
        var flipped: CGImage?
        print(direction)
        if direction == "V" {
            flipped = flipVertically(currentImage)
        } else {
            flipped = flipHorizontally(currentImage)
        }
        if let newImage = flipped {
            // flip 参与Undo
            pushUndoSnapshot()
            commitCGImage(newImage)
        }
    }
    func changeCanvasSize(_ config: CanvasSizeConfig) {
        guard let image = renderedImage,
              let pixelSize = renderedPixelSize else { return }
        let currentImage = LoadedImage(image: image, pixelSize: pixelSize)
        if let newCGImage = InfraView.changeCanvasSize(originalImage: currentImage, config: config) {
            pushUndoSnapshot()
            commitCGImage(newCGImage)
        } else {
            // 处理错误
            print("Failed to change canvas size")
        }
    }
    func setSelectionPx(rectPx: CGRect?) {
        selectionRectPx = rectPx
    }

    func setRenderedImage(_ img: LoadedImage?) {
        renderedImage = img?.image
        renderedPixelSize = img?.pixelSize
    }
}
