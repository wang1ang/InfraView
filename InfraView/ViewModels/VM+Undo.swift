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
    func applyImage(_ cg: CGImage) {
        currentCGImage = cg
        let w = cg.width; let h = cg.height
        let size = NSSize(width: w, height: h)
        let nsImage = NSImage(cgImage: cg, size: size)
        print("applyImage: \(size)")
        setProcessedImage(LoadedImage(image: nsImage, pixelSize: size))
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


