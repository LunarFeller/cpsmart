import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = HistoryStore()
    private let pinboardStore = PinboardStore()
    private let monitor = ClipboardMonitor()
    private let pasteController = PasteController()
    private let shortcutStore = ShortcutStore()
    private let updateController = UpdateController()
    private lazy var historyWindow = HistoryWindowController(shortcutStore: shortcutStore)
    private lazy var aboutWindow = AboutWindowController(shortcutStore: shortcutStore)
    private lazy var shortcutSettingsWindow = ShortcutSettingsWindowController(
        shortcutStore: shortcutStore
    )
    private var hotKey: GlobalHotKey?
    private var shouldRegisterGlobalHotKey = true
    private var isRecordingShortcut = false
    private var statusItem: NSStatusItem!
    private var openHistoryMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var appearanceMenuItem: NSMenuItem!
    private var checkForUpdatesMenuItem: NSMenuItem!
    private var automaticUpdatesMenuItem: NSMenuItem!

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
        configureShortcutSettings()
        configureStatusItem()
        configureClipboardMonitor()
        updateController.onStateChange = { [weak self] in
            self?.refreshUpdateMenuItems()
        }

        // 演示模式（仅 DEBUG）：跳过快捷键注册，避免与正在运行的正式版冲突。
        let isDemoMode = CommandLine.arguments.contains("--demo-data")
        let shouldShowShortcutSettings = CommandLine.arguments.contains("--show-shortcut-settings")
        shouldRegisterGlobalHotKey = !isDemoMode

        if !isDemoMode {
            registerInitialGlobalHotKey()
            updateController.startAutomaticChecks()
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
        // Useful for packaged update-check smoke tests; the installed bundle provides the version
        // that is compared with the latest stable GitHub Release.
        if CommandLine.arguments.contains("--check-for-updates") {
            DispatchQueue.main.async { [weak self] in
                self?.updateController.checkForUpdates()
            }
        }
        if shouldShowShortcutSettings {
            DispatchQueue.main.async { [weak self] in
                self?.shortcutSettingsWindow.show()
            }
        }

        #if DEBUG
        // 开发用：`--demo-data` 用内置演示数据打开浮窗，不读写真实历史，便于截图审查 UI。
        // 可选 `--demo-query <词>` 预填搜索词；`--demo-light` 强制浅色外观（不写入设置）。
        if isDemoMode {
            monitor.isPaused = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !shouldShowShortcutSettings else { return }
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
                if let previewIndex = CommandLine.arguments.firstIndex(of: "--demo-preview-index"),
                   CommandLine.arguments.indices.contains(previewIndex + 1),
                   let index = Int(CommandLine.arguments[previewIndex + 1]) {
                    // 等集合视图完成首轮布局，确保选中卡片已经有可用于锚定的 window。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.historyWindow.showDemoPreview(at: index)
                    }
                }
                if let sessionIndex = CommandLine.arguments.firstIndex(of: "--demo-preview-session"),
                   CommandLine.arguments.indices.contains(sessionIndex + 1),
                   let index = Int(CommandLine.arguments[sessionIndex + 1]) {
                    let logURL = URL(fileURLWithPath: "/tmp/cpsmart-preview-session.log")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.historyWindow.runDemoPreviewSession(textIndex: index, logURL: logURL)
                    }
                }
                if CommandLine.arguments.contains("--demo-new-pinboard-sheet") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.historyWindow.showDemoNewPinboardSheet()
                    }
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

    private func configureShortcutSettings() {
        shortcutSettingsWindow.onAttemptChange = { [weak self] action, gesture in
            self?.attemptShortcutChange(action: action, gesture: gesture)
        }
        shortcutSettingsWindow.onAttemptReset = { [weak self] in
            self?.attemptShortcutReset()
        }
        shortcutSettingsWindow.onAttemptResetAction = { [weak self] action in
            self?.attemptShortcutReset(action: action)
        }
        shortcutSettingsWindow.onAttemptSwap = {
            [weak self] action, conflictingAction, gesture in
            self?.attemptShortcutSwap(
                action: action,
                with: conflictingAction,
                requestedGesture: gesture
            )
        }
        shortcutSettingsWindow.onRecordingStateChanged = { [weak self] recording in
            self?.setShortcutRecording(recording)
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
        openHistoryMenuItem = NSMenuItem(
            title: openHistoryMenuTitle,
            action: #selector(showHistoryFromMenu),
            keyEquivalent: ""
        )
        menu.addItem(openHistoryMenuItem)
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
            title: "快捷键设置…",
            action: #selector(showShortcutSettings),
            keyEquivalent: ""
        ))

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

        checkForUpdatesMenuItem = NSMenuItem(
            title: updateController.menuItemTitle,
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        menu.addItem(checkForUpdatesMenuItem)

        automaticUpdatesMenuItem = NSMenuItem(
            title: "自动检查更新",
            action: #selector(toggleAutomaticUpdates),
            keyEquivalent: ""
        )
        menu.addItem(automaticUpdatesMenuItem)
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
        openHistoryMenuItem.title = openHistoryMenuTitle
        pauseMenuItem.state = monitor.isPaused ? .on : .off
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        refreshUpdateMenuItems()
    }

    private func refreshUpdateMenuItems() {
        guard checkForUpdatesMenuItem != nil, automaticUpdatesMenuItem != nil else { return }
        checkForUpdatesMenuItem.title = updateController.menuItemTitle
        checkForUpdatesMenuItem.isEnabled = updateController.activity == .idle
        automaticUpdatesMenuItem.state = updateController.automaticChecksEnabled ? .on : .off
    }

    @objc private func selectAppearanceMode(_ sender: NSMenuItem) {
        let mode = AppearanceMode.allCases[sender.tag]
        AppearanceMode.current = mode
        historyWindow.applyAppearanceMode()
        shortcutSettingsWindow.applyAppearanceMode()
    }

    private func showHistory() {
        historyWindow.show(entries: store.entries, pinboards: activePinboardStore.boards)
    }

    @objc private func showHistoryFromMenu() {
        showHistory()
    }

    @objc private func showShortcutSettings() {
        shortcutSettingsWindow.show()
    }

    private var openHistoryMenuTitle: String {
        "打开剪贴板历史（\(shortcutStore.displayString(for: .toggleHistory))）"
    }

    private func registerInitialGlobalHotKey() {
        let gesture = shortcutStore.primaryBinding(for: .toggleHistory)
        hotKey = makeGlobalHotKey(for: gesture)
        if hotKey == nil {
            showAlert(
                title: "快捷键注册失败",
                message: "\(gesture.displayString) 可能已被系统或其他应用占用。你仍可从菜单栏打开 cpsmart，并在“快捷键设置”中更换。"
            )
        }
    }

    private func makeGlobalHotKey(for gesture: ShortcutGesture) -> GlobalHotKey? {
        GlobalHotKey(gesture: gesture) { [weak self] in
            self?.showHistory()
        }
    }

    private func attemptShortcutChange(
        action: ShortcutActionID,
        gesture: ShortcutGesture
    ) -> String? {
        if let issue = shortcutStore.validate(gesture, for: action) {
            return issue.message
        }

        if action == .toggleHistory, shouldRegisterGlobalHotKey {
            if hotKey?.gesture != gesture {
                guard let candidate = makeGlobalHotKey(for: gesture) else {
                    return "无法使用 \(gesture.displayString)：该快捷键可能已被系统或其他应用占用。原快捷键仍然有效。"
                }
                guard shortcutStore.set(gesture, for: action) == nil else {
                    return "无法保存该快捷键。"
                }
                hotKey = candidate
                openHistoryMenuItem?.title = openHistoryMenuTitle
                return nil
            }
        }

        if let issue = shortcutStore.set(gesture, for: action) {
            return issue.message
        }
        openHistoryMenuItem?.title = openHistoryMenuTitle
        return nil
    }

    private func attemptShortcutReset() -> String? {
        let defaultGlobal = ShortcutDefaults.bindings[.toggleHistory]!.first!
        if shouldRegisterGlobalHotKey, hotKey?.gesture != defaultGlobal {
            guard let candidate = makeGlobalHotKey(for: defaultGlobal) else {
                return "无法恢复默认：\(defaultGlobal.displayString) 可能已被系统或其他应用占用。当前设置保持不变。"
            }
            shortcutStore.resetToDefaults()
            hotKey = candidate
        } else {
            shortcutStore.resetToDefaults()
        }
        openHistoryMenuItem?.title = openHistoryMenuTitle
        return nil
    }

    private func attemptShortcutReset(action: ShortcutActionID) -> String? {
        if let issue = shortcutStore.validateReset(for: action) {
            return "无法恢复默认：\(issue.message)"
        }

        if action == .toggleHistory, shouldRegisterGlobalHotKey {
            let defaultGesture = shortcutStore.defaultBindings(for: action).first!
            guard let candidate = makeGlobalHotKey(for: defaultGesture) else {
                return "无法恢复默认：\(defaultGesture.displayString) 可能已被系统或其他应用占用。当前设置保持不变。"
            }
            guard shortcutStore.resetToDefault(action) == nil else {
                return "无法恢复该快捷键。"
            }
            hotKey = candidate
        } else if let issue = shortcutStore.resetToDefault(action) {
            return issue.message
        }

        openHistoryMenuItem?.title = openHistoryMenuTitle
        return nil
    }

    private func attemptShortcutSwap(
        action: ShortcutActionID,
        with conflictingAction: ShortcutActionID,
        requestedGesture: ShortcutGesture
    ) -> String? {
        if let issue = shortcutStore.validateSwap(
            action,
            with: conflictingAction,
            requestedGesture: requestedGesture
        ) {
            return "无法交换：\(issue.message)"
        }

        let replacementGesture = shortcutStore.primaryBinding(for: action)
        let newGlobalGesture: ShortcutGesture? = if action == .toggleHistory {
            requestedGesture
        } else if conflictingAction == .toggleHistory {
            replacementGesture
        } else {
            nil
        }

        var candidateHotKey: GlobalHotKey?
        if shouldRegisterGlobalHotKey, let newGlobalGesture {
            guard let candidate = makeGlobalHotKey(for: newGlobalGesture) else {
                return "无法交换：\(newGlobalGesture.displayString) 不能注册为全局快捷键。当前设置保持不变。"
            }
            candidateHotKey = candidate
        }

        if let issue = shortcutStore.swap(
            action,
            with: conflictingAction,
            requestedGesture: requestedGesture
        ) {
            return "无法交换：\(issue.message)"
        }
        if let candidateHotKey { hotKey = candidateHotKey }
        openHistoryMenuItem?.title = openHistoryMenuTitle
        return nil
    }

    private func setShortcutRecording(_ recording: Bool) -> String? {
        guard shouldRegisterGlobalHotKey else { return nil }
        if recording {
            guard !isRecordingShortcut else { return nil }
            isRecordingShortcut = true
            // Carbon 会先拦截当前全局组合；录制期间必须临时注销，录制控件才能收到它。
            hotKey = nil
            return nil
        }

        guard isRecordingShortcut else { return nil }
        isRecordingShortcut = false
        guard hotKey == nil else { return nil }
        let gesture = shortcutStore.primaryBinding(for: .toggleHistory)
        guard let restored = makeGlobalHotKey(for: gesture) else {
            return "无法恢复 \(gesture.displayString)：该快捷键可能刚被系统或其他应用占用。请重新录制一个全局快捷键。"
        }
        hotKey = restored
        return nil
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

    @objc private func checkForUpdates() {
        updateController.checkForUpdates()
    }

    @objc private func toggleAutomaticUpdates() {
        updateController.setAutomaticChecksEnabled(!updateController.automaticChecksEnabled)
        refreshUpdateMenuItems()
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
