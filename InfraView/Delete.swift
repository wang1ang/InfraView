// Delete.swift

import AppKit
import SwiftUI
import ObjectiveC

// MARK: activate Edit -> Delete
private final class DeleteCommandResponder: NSResponder, NSUserInterfaceValidations {
    let onDelete: () -> Void

    init(onDelete: @escaping () -> Void) {
        self.onDelete = onDelete
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    @objc func delete(_ sender: Any?) {
        onDelete()
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(delete(_:)) { return true }
        return true
    }
}

struct InstallDeleteResponder: NSViewRepresentable {
    let onDelete: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        v.isHidden = true

        DispatchQueue.main.async {
            guard let win = v.window else { return }

            // 只安装一次
            struct Assoc { static var key: UInt8 = 0 }
            if objc_getAssociatedObject(win, &Assoc.key) != nil { return }

            let hook = DeleteCommandResponder(onDelete: onDelete)
            hook.nextResponder = win.nextResponder
            win.nextResponder = hook
            objc_setAssociatedObject(win, &Assoc.key, hook, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}


// 绑定系统 Edit > Delete 的快捷键（只保留一个）
@objc protocol DeleteAction {func delete(_ sender: Any?)} // 只为拿到 #selector(delete:)

func bindDeleteToCommandBackspace() {
    //let deleteSel = Selector(("delete:"))
    let deleteSel = #selector(DeleteAction.delete(_:))

    func apply() {
        guard
            let main = NSApp.mainMenu,
            // 找到含有 delete: 的那个 Edit 菜单
            let editMenu = main.items.first(where: {
                $0.submenu?.items.contains(where: { $0.action == deleteSel }) ?? false
            })?.submenu,
            let deleteItem = editMenu.items.first(where: { $0.action == deleteSel })
        else { return }
        // 显示 ⌘⌫
        deleteItem.keyEquivalent = String(UnicodeScalar(0x08)!) // Backspace
        deleteItem.keyEquivalentModifierMask = NSEvent.ModifierFlags.command
    }

    // 菜单有时会被重建，延迟一次并在激活/变更时重绑更稳
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: apply)
    NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in apply() }
    NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { _ in apply() }
}
