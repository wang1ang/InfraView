//
//  Notifications.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import Foundation

/// 应用内通知名称定义
extension Notification.Name {
    // MARK: - 文件操作
    static let infraSave = Notification.Name("infraSave")
    static let openFileBySystem = Notification.Name("InfraView.OpenFileBySystem")
    
    // MARK: - 导航
    static let infraNext = Notification.Name("InfraView.Next")
    static let infraPrev = Notification.Name("InfraView.Prev")
    
    // MARK: - 编辑操作
    static let infraDelete = Notification.Name("InfraView.Delete")
    static let infraRotate = Notification.Name("InfraView.Rotate")
    static let infraFlip = Notification.Name("InfraView.Flip")
    static let infraCanvasSize = Notification.Name("InfraView.CanvasSize")
    static let infraToggleStar = Notification.Name("InfraView.ToggleStar")
    static let infraCopy = Notification.Name("InfraView.Copy")
    static let infraCut = Notification.Name("InfraView.Cut")
    static let infraCrop = Notification.Name("InfraView.Crop")
    static let infraSelectAll = Notification.Name("InfraView.SelectAll")
    
    // MARK: - 撤销/重做
    static let infraUndo = Notification.Name("InfraView.Undo")
    static let infraRedo = Notification.Name("InfraView.Redo")
    
    // MARK: - UI 状态
    static let infraToggleStatusBar = Notification.Name("InfraView.ToggleStatusBar")
}

