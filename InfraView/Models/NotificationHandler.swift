//
//  NotificationHandler.swift
//  InfraView
//
//  Created by 王洋 on 28/11/2025.
//

import Combine
import SwiftUI

class NotificationHandler: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    private var toolbarWasVisible = true
    private var statusBarWasVisible = true
    
    func setupHandlers(
        store: ImageStore,
        viewerVM: ViewerViewModel,
        fitMode: Binding<FitMode>
    ) {
        // 导航相关
        let nextPrevPublisher = Publishers.Merge(
            NotificationCenter.default.publisher(for: .infraNext),
            NotificationCenter.default.publisher(for: .infraPrev)
        )
        nextPrevPublisher
            .sink { notification in
                guard let win = viewerVM.window, win.isKeyWindow else { return }
                switch notification.name {
                case .infraNext:
                    self.next(store)
                case .infraPrev:
                    self.previous(store)
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // 全屏相关通知
        let fullScreenPublisher = Publishers.Merge(
            NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification),
            NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)
        )
        fullScreenPublisher
            .sink { notification in
                guard let win = viewerVM.window, win.isKeyWindow else { return }
                switch notification.name {
                case NSWindow.willEnterFullScreenNotification:
                    self.onEnterFullScreen(win)
                case NSWindow.didExitFullScreenNotification:
                    self.onExitFullScreen(win)
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // 图像操作相关（旋转、翻转、画布大小）
        let imageOperationPublisher = Publishers.Merge(
            NotificationCenter.default.publisher(for: .infraRotate),
            NotificationCenter.default.publisher(for: .infraFlip)
            // .infraCanvasSize will throw an error: ViewBridge to RemoteViewService Terminated
        )
        imageOperationPublisher
            .sink { note in
                guard let win = viewerVM.window, win.isKeyWindow else { return }
                switch note.name {
                case .infraRotate:
                    let q = (note.object as? Int) ?? 0
                    viewerVM.rotateCurrentImage(fitMode: fitMode.wrappedValue, by: q)
                case .infraFlip:
                    if let direction = note.object as? String {
                        viewerVM.flipCurrentImage(by: direction)
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // 剪贴板操作相关（复制、剪切）
        let clipboardPublisher = Publishers.Merge(
            NotificationCenter.default.publisher(for: .infraCopy),
            NotificationCenter.default.publisher(for: .infraCut)
        )
        clipboardPublisher
            .sink { note in
                guard viewerVM.window?.isKeyWindow == true else { return }
                
                switch note.name {
                case .infraCopy:
                    print("InfraView Copy fired")
                    let copiedSelection = viewerVM.copySelectionToPasteboard()
                    if !copiedSelection {
                        // copy file
                        guard let idx = store.selection, idx < store.imageURLs.count else { return }
                        let url = store.imageURLs[idx]
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.writeObjects([url as NSURL])
                    }
                case .infraCut:
                    if viewerVM.copySelectionToPasteboard() {
                        viewerVM.eraseSelection()
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // 编辑操作相关（撤销、重做、文件打开）
        let editOperationPublisher = Publishers.Merge3(
            NotificationCenter.default.publisher(for: .infraUndo),
            NotificationCenter.default.publisher(for: .infraRedo),  // 这里有 redo
            NotificationCenter.default.publisher(for: .openFileBySystem)
        )

        editOperationPublisher
            .sink { note in
                switch note.name {
                case .infraUndo:
                    guard viewerVM.window?.isKeyWindow == true else { return }
                    viewerVM.undo()
                case .infraRedo:  // 这里处理 redo
                    guard viewerVM.window?.isKeyWindow == true else { return }
                    viewerVM.redo()
                case .openFileBySystem:
                    if let urls = note.object as? [URL] {
                        store.load(urls: urls)
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func next(_ store: ImageStore) { guard let sel = store.selection, !store.imageURLs.isEmpty else { return }; store.selection = (sel + 1) % store.imageURLs.count }
    private func previous(_ store: ImageStore) { guard let sel = store.selection, !store.imageURLs.isEmpty else { return }; store.selection = (sel - 1 + store.imageURLs.count) % store.imageURLs.count }

    private func onEnterFullScreen(_ win: NSWindow) {
        toolbarWasVisible = win.toolbar?.isVisible ?? true
        win.toolbar?.isVisible = false
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        if #available(macOS 11.0, *) { win.titlebarSeparatorStyle = .none }
        
        statusBarWasVisible = StatusBarStore.shared.isVisible
        StatusBarStore.shared.isVisible = false
        
        NSCursor.setHiddenUntilMouseMoves(true)
    }
    private func onExitFullScreen(_ win: NSWindow) {
        win.toolbar?.isVisible = toolbarWasVisible
        win.titleVisibility = .visible
        win.titlebarAppearsTransparent = false
        if #available(macOS 11.0, *) { win.titlebarSeparatorStyle = .automatic }
        StatusBarStore.shared.isVisible = statusBarWasVisible
    }
}
