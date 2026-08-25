import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = HistoryStore()
    private let pinboardStore = PinboardStore()
    private let monitor = ClipboardMonitor()
    private let pasteController = PasteController()
    private let historyWindow = HistoryWindowController()
    private let aboutWindow = AboutWindowController()
    private var hotKey: GlobalHotKey?
    private var statusItem: NSStatusItem!
    private var pauseMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var appearanceMenuItem: NSMenuItem!

    #if DEBUG
    private var demoPinboardStore: PinboardStore?
    private var demoPinboardFileURL: URL?
    #endif

    private var activePinboardStore: PinboardStore {
        #if DEBUG
        if let demoPinboardStore { return demoPinboardStore }
        #endif
        return pinboardStore
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureApplicationIcon()
        configureHistoryWindow()
        configureStatusItem()
        configureClipboardMonitor()

        // 演示模式（仅 DEBUG）：跳过快捷键注册，避免与正在运行的正式版冲突。
        let isDemoMode = CommandLine.arguments.contains("--demo-data")

        if !isDemoMode {
            hotKey = GlobalHotKey { [weak self] in
                self?.showHistory()
            }

            if hotKey == nil {
                showAlert(
                    title: "快捷键注册失败",
                    message: "⇧⌘V 可能已被其他应用占用。你仍可从菜单栏打开 cpsmart。"
                )
            }
        }

        // Useful for automated UI smoke tests without requiring Accessibility permission.
        if CommandLine.arguments.contains("--show-history") {
            DispatchQueue.main.async { [weak self] in
                self?.showHistory()
            }
        }
        if CommandLine.arguments.contains("--show-about") {
            DispatchQueue.main.async { [weak self] in
                self?.aboutWindow.show()
            }
        }

        #if DEBUG
        // 开发用：`--demo-data` 用内置演示数据打开浮窗，不读写真实历史，便于截图审查 UI。
        // 可选 `--demo-query <词>` 预填搜索词；`--demo-light` 强制浅色外观（不写入设置）。
        if isDemoMode {
            monitor.isPaused = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let demoPinboardFileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "cpsmart-demo-pinboards-\(ProcessInfo.processInfo.processIdentifier).json"
                    )
                try? FileManager.default.removeItem(at: demoPinboardFileURL)
                self.demoPinboardFileURL = demoPinboardFileURL
                self.demoPinboardStore = PinboardStore(
                    fileURL: demoPinboardFileURL,
                    initialBoards: DemoData.makePinboards()
                )
                self.historyWindow.show(
                    entries: DemoData.makeEntries(),
                    pinboards: self.activePinboardStore.boards
                )
                if CommandLine.arguments.contains("--demo-light") {
                    self.historyWindow.applyAppearanceMode(.light)
                } else if CommandLine.arguments.contains("--demo-dark") {
                    self.historyWindow.applyAppearanceMode(.dark)
                }
                if let pinboardIndex = CommandLine.arguments.firstIndex(of: "--demo-pinboard"),
                   CommandLine.arguments.indices.contains(pinboardIndex + 1),
                   let index = Int(CommandLine.arguments[pinboardIndex + 1]) {
                    self.historyWindow.applyDemoPinboard(at: index)
                }
                if let queryIndex = CommandLine.arguments.firstIndex(of: "--demo-query"),
                   CommandLine.arguments.indices.contains(queryIndex + 1) {
                    self.historyWindow.applyDemoQuery(CommandLine.arguments[queryIndex + 1])
                }
                if let snapshotIndex = CommandLine.arguments.firstIndex(of: "--demo-snapshot"),
                   CommandLine.arguments.indices.contains(snapshotIndex + 1) {
                    let snapshotURL = URL(
                        fileURLWithPath: CommandLine.arguments[snapshotIndex + 1]
                    )
                    var snapshotDelay = 0.6
                    if let delayIndex = CommandLine.arguments.firstIndex(of: "--demo-snapshot-delay"),
                       CommandLine.arguments.indices.contains(delayIndex + 1),
                       let configuredDelay = Double(CommandLine.arguments[delayIndex + 1]) {
                        snapshotDelay = max(0, configuredDelay)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + snapshotDelay) { [weak self] in
                        _ = self?.historyWindow.writeDemoSnapshot(to: snapshotURL)
                    }
                }
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        #if DEBUG
        if let demoPinboardFileURL {
            try? FileManager.default.removeItem(at: demoPinboardFileURL)
        }
        #endif
    }

    private func configureApplicationIcon() {
        guard let iconURL = Bundle.main.url(forResource: "CPSmartAppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else { return }
        NSApp.applicationIconImage = icon
    }

    private func configureClipboardMonitor() {
        monitor.isPaused = UserDefaults.standard.bool(forKey: "capturePaused")
        monitor.onCapture = { [weak self] payload, sourceAppName, sourceAppBundleID in
            guard let self else { return }
            let capturedEntry = self.store.add(
                payload,
                sourceAppName: sourceAppName,
                sourceAppBundleID: sourceAppBundleID
            )
            self.historyWindow.refresh(
                entries: self.store.entries,
                selectingEntryID: capturedEntry.id
            )
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
        historyWindow.onTogglePin = { [weak self] entry in
            guard let self else { return }
            self.store.togglePin(id: entry.id)
            self.historyWindow.refresh(entries: self.store.entries)
        }
        historyWindow.onCreatePinboard = { [weak self] name, color in
            guard let self else { return nil }
            let store = self.activePinboardStore
            let board = store.create(name: name, color: color)
            self.historyWindow.refresh(pinboards: store.boards)
            return board
        }
        historyWindow.onRenamePinboard = { [weak self] id, name in
            guard let self else { return }
            let store = self.activePinboardStore
            store.rename(id: id, to: name)
            self.historyWindow.refresh(pinboards: store.boards)
        }
        historyWindow.onSetPinboardColor = { [weak self] id, color in
            guard let self else { return }
            let store = self.activePinboardStore
            store.setColor(id: id, color: color)
            self.historyWindow.refresh(pinboards: store.boards)
        }
        historyWindow.onDeletePinboard = { [weak self] id in
            guard let self else { return }
            let store = self.activePinboardStore
            store.removeBoard(id: id)
            self.historyWindow.refresh(pinboards: store.boards)
        }
        historyWindow.onAddToPinboard = { [weak self] entry, boardID in
            guard let self else { return }
            let store = self.activePinboardStore
            store.add(entry, to: boardID)
            self.historyWindow.refresh(pinboards: store.boards)
        }
        historyWindow.onRemoveFromPinboard = { [weak self] entry, boardID in
            guard let self else { return }
            let store = self.activePinboardStore
            store.removeEntry(id: entry.id, from: boardID)
            self.historyWindow.refresh(pinboards: store.boards)
        }
        historyWindow.onMovePinboardEntry = { [weak self] entryID, boardID, insertionIndex in
            guard let self else { return }
            let store = self.activePinboardStore
            store.moveEntry(
                id: entryID,
                toInsertionIndex: insertionIndex,
                in: boardID
            )
            self.historyWindow.refresh(pinboards: store.boards)
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

        // 外观：跟随系统 / 浅色 / 深色
        appearanceMenuItem = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let appearanceSubmenu = NSMenu()
        for (index, mode) in AppearanceMode.allCases.enumerated() {
            let item = NSMenuItem(
                title: mode.displayName,
                action: #selector(selectAppearanceMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            appearanceSubmenu.addItem(item)
        }
        appearanceSubmenu.delegate = self
        appearanceMenuItem.submenu = appearanceSubmenu
        menu.addItem(appearanceMenuItem)

        menu.addItem(NSMenuItem(
            title: "清空历史…",
            action: #selector(clearHistory),
            keyEquivalent: ""
        ))
        // 按住 Option 出现：连置顶记录一起清空
        let clearAllItem = NSMenuItem(
            title: "清空全部历史（含置顶）…",
            action: #selector(clearAllHistory),
            keyEquivalent: ""
        )
        clearAllItem.isAlternate = true
        clearAllItem.keyEquivalentModifierMask = [.option]
        menu.addItem(clearAllItem)
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
        if menu === appearanceMenuItem.submenu {
            for item in menu.items {
                item.state = AppearanceMode.allCases[item.tag] == AppearanceMode.current
                    ? .on
                    : .off
            }
            return
        }
        pauseMenuItem.state = monitor.isPaused ? .on : .off
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func selectAppearanceMode(_ sender: NSMenuItem) {
        let mode = AppearanceMode.allCases[sender.tag]
        AppearanceMode.current = mode
        historyWindow.applyAppearanceMode()
    }

    private func showHistory() {
        historyWindow.show(entries: store.entries, pinboards: activePinboardStore.boards)
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
        alert.messageText = "清空剪贴板历史？"
        alert.informativeText = "置顶的记录会保留。此操作无法撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clear()
        historyWindow.refresh(entries: store.entries)
    }

    @objc private func clearAllHistory() {
        let alert = NSAlert()
        alert.messageText = "清空全部剪贴板历史（含置顶）？"
        alert.informativeText = "置顶的记录也会一并删除。此操作无法撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "全部清空")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clearAll()
        historyWindow.refresh(entries: store.entries)
    }

    @objc private func showAbout() {
        aboutWindow.show()
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
