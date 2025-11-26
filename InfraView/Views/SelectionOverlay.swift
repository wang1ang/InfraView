//
//  SelectionOverlay.swift
//  InfraView
//
//  Created by 王洋 on 26/11/2025.
//

import SwiftUI


final class SelectionOverlay {
    let layer = CAShapeLayer()
    private weak var hostView: NSView?
    private var pendingClickWorkItem: DispatchWorkItem?

    // 🟢 手势识别器
    private lazy var doubleClickRecognizer: NSClickGestureRecognizer = {
        let dbl = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
                dbl.numberOfClicksRequired = 2
                dbl.buttonMask = 0x1
                return dbl
    }()
    private lazy var clickRecognizer: NSClickGestureRecognizer = {
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
                return click
    }()

    // 🟢 回调
    var onDoubleClick: ((NSPoint) -> Void)?
    var onClick: ((NSPoint) -> Void)?

    init() {
        layer.fillColor = nil
        layer.strokeColor = NSColor.controlAccentColor.cgColor
        layer.lineWidth = 1
        layer.lineDashPattern = [4, 3]
        layer.zPosition = 1_000_000
    }
    func attach(to doc: NSView) {
        doc.wantsLayer = true
        guard let hostLayer = doc.layer else { return }
        if layer.superlayer !== hostLayer {
            detach()
            hostLayer.addSublayer(layer)
            hostView = doc
        }
        attachGestureRecognizers(to: doc)
    }
    func detach(_ caller: String = #function) {
        print("detach: \(caller)")
        // 取消单击任务
        pendingClickWorkItem?.cancel()
        pendingClickWorkItem = nil
        
        // 🟢 清理手势识别器
        detachGestureRecognizers()
        layer.removeFromSuperlayer()
        layer.path = nil
        hostView = nil
    }
    private func attachGestureRecognizers(to doc: NSView) {
        // 确保没有重复添加
        detachGestureRecognizers()
        
        doc.addGestureRecognizer(doubleClickRecognizer)
        doc.addGestureRecognizer(clickRecognizer)
    }
    
    private func detachGestureRecognizers() {
        doubleClickRecognizer.view?.removeGestureRecognizer(doubleClickRecognizer)
        clickRecognizer.view?.removeGestureRecognizer(clickRecognizer)
    }
    
    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        print("🟠 SelectionOverlay 双击")
        guard let doc = hostView else { return }
        let location = gesture.location(in: doc)
        pendingClickWorkItem?.cancel()
        self.onDoubleClick?(location)
    }
    
    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        print("🟣 SelectionOverlay 单击")
        guard let doc = hostView else { return }
        let location = gesture.location(in: doc)
        pendingClickWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onClick?(location)
        }
        pendingClickWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
    
    func update(rectInDoc: CGRect?) {
        guard let r = rectInDoc, r.width >= 0, r.height >= 0 else {
            detach()
            return
        }
        let path = CGMutablePath()
        path.addRect(r)
        layer.path = path
    }
    func clear() {
        layer.path = nil
        detach()
    }
}

