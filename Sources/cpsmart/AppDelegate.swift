import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = HistoryStore()
    private let monitor = ClipboardMonitor()
    private let pasteController = PasteController()
    private let historyWindow = HistoryWindowController()
    private var hotKey: GlobalHotKey?
    private var statusItem: NSStatusItem!
    private var pauseMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureHistoryWindow()
        configureStatusItem()
        configureClipboardMonitor()

        hotKey = GlobalHotKey { [weak self] in
            self?.showHistory()
        }

        if hotKey == nil {
            showAlert(
                title: "快捷键注册失败",
                message: "⇧⌘V 可能已被其他应用占用。你仍可从菜单栏打开 cpsmart。"
            )
        }

        // Useful for automated UI smoke tests without requiring Accessibility permission.
        if CommandLine.arguments.contains("--show-history") {
            DispatchQueue.main.async { [weak self] in
                self?.showHistory()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    private func configureClipboardMonitor() {
        monitor.isPaused = UserDefaults.standard.bool(forKey: "capturePaused")
        monitor.onCapture = { [weak self] payload, sourceAppName, sourceAppBundleID in
            guard let self else { return }
            self.store.add(
                payload,
                sourceAppName: sourceAppName,
                sourceAppBundleID: sourceAppBundleID
            )
            self.historyWindow.refresh(entries: self.store.entries)
        }
        monitor.start()
    }

    private func configureHistoryWindow() {
        historyWindow.onChoose = { [weak self] entry in
            guard let self else { return }
            self.monitor.write(entry.payload)
        }
        historyWindow.onPaste = { [weak self] targetApplication in
            self?.pasteController.paste(to: targetApplication) ?? .targetUnavailable
        }
        historyWindow.onDelete = { [weak self] entry in
            guard let self else { return }
            self.store.remove(id: entry.id)
            self.historyWindow.refresh(entries: self.store.entries)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "cpsmart"
            )
            button.toolTip = "cpsmart 剪贴板历史"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(
            title: "打开剪贴板历史（⇧⌘V）",
            action: #selector(showHistoryFromMenu),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())

        pauseMenuItem = NSMenuItem(
            title: "暂停记录",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        menu.addItem(pauseMenuItem)

        loginMenuItem = NSMenuItem(
            title: "登录时启动",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        menu.addItem(loginMenuItem)

        menu.addItem(NSMenuItem(
            title: "清空历史…",
            action: #selector(clearHistory),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "关于 cpsmart",
            action: #selector(showAbout),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "退出 cpsmart",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        pauseMenuItem.state = monitor.isPaused ? .on : .off
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func showHistory() {
        historyWindow.show(entries: store.entries)
    }

    @objc private func showHistoryFromMenu() {
        showHistory()
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
        UserDefaults.standard.set(monitor.isPaused, forKey: "capturePaused")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(
                title: "无法更改登录启动设置",
                message: "请先把 cpsmart 拖入“应用程序”文件夹，然后重试。\n\n\(error.localizedDescription)"
            )
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空全部剪贴板历史？"
        alert.informativeText = "此操作无法撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clear()
        historyWindow.refresh(entries: store.entries)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "cpsmart",
            .applicationVersion: "1.6.0",
            .credits: NSAttributedString(string: "轻量、私密的本地剪贴板历史工具。")
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
