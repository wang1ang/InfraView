//
//  VM+Undo.swift
//  InfraView
//
//  Created by 王洋 on 14/11/2025.
//
import AppKit

extension ViewerViewModel {
    // 每次要修改图像前调用：把当前状态推入 undo 栈
    func pushUndoSnapshot() {
        guard let cg = currentCGImage else {
            // 如果 currentCGImage 还没初始化，尝试用 processedImage 填一下
            if let img = processedImage, let c = img.cgImageSafe {
                currentCGImage = c
            } else { return }
            return pushUndoSnapshot()
        }

        undoStack.append(cg)
        if undoStack.count > maxHistory {
            undoStack.removeFirst()
        }
        // 一旦有新的编辑操作，redo 栈清空
        redoStack.removeAll()
    }

    // 用某个 CGImage 覆盖当前图像
    /*
    func applyImage(_ cg: CGImage) {
        currentCGImage = cg
        let size = processedImage?.size ?? NSSize(width: cg.width, height: cg.height)
        let nsImage = NSImage(cgImage: cg, size: size)
        processedImage = nsImage
    }*/
    func applyImage(_ cg: CGImage) {
        currentCGImage = cg

        // 用 CGImage 自己的像素尺寸来当显示尺寸，不再继承旧图的 size
        // 如果想考虑 Retina，可以除以屏幕 scale：
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        let size = NSSize(
            width:  CGFloat(cg.width)  / scale,
            height: CGFloat(cg.height) / scale
        )

        let nsImage = NSImage(cgImage: cg, size: size)
        processedImage = nsImage
    }


    func undo() {
        guard let last = undoStack.popLast() else { return }
        if let cur = currentCGImage {
            redoStack.append(cur)
        }
        applyImage(last)
        selectionRectPx = nil
    }

    func redo() {
        guard let last = redoStack.popLast() else { return }
        if let cur = currentCGImage {
            undoStack.append(cur)
        }
        applyImage(last)
        selectionRectPx = nil
    }

    // 在加载新图片时，记得重置历史
    func resetHistoryForNewImage(from image: NSImage) {
        if let cg = image.cgImageSafe {
            currentCGImage = cg
        } else {
            currentCGImage = nil
        }
        undoStack.removeAll()
        redoStack.removeAll()
        selectionRectPx = nil
    }
}


