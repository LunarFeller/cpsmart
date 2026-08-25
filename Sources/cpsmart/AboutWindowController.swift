import AppKit

final class AboutWindowController: NSWindowController, NSWindowDelegate {
    private let preferredSize = NSSize(width: 660, height: 720)

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: preferredSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = "关于 cpsmart"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 600, height: 620)
        window.setContentSize(preferredSize)
        window.center()
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = makeContentView()
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            center(window: window, on: screenUnderMouse())
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func center(window: NSWindow, on screen: NSScreen?) {
        guard let screen else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }

    private func makeContentView() -> NSView {
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow
        background.state = .active

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let contentStack = NSStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 16
        documentView.addSubview(contentStack)

        let sections = [
            makeHero(),
            makeQuickStartCard(),
            makeKeyboardCard(),
            makePointerCard(),
            makePrivacyCard(),
            makeFooter()
        ]
        for section in sections {
            contentStack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        background.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: background.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 34),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -34),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 46),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -30)
        ])
        return background
    }

    private func makeHero() -> NSView {
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = loadApplicationIcon()
        icon.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 88),
            icon.heightAnchor.constraint(equalToConstant: 88)
        ])

        let name = label("cpsmart", size: 28, weight: .bold)
        let version = label(displayVersion, size: 12, weight: .medium, color: .secondaryLabelColor)
        let tagline = label("快速找到刚刚复制的内容", size: 15, weight: .medium)
        let privacy = label("轻量、原生、完全本地。剪贴板历史不会上传。", size: 12.5, color: .secondaryLabelColor)

        let text = NSStackView(views: [name, version, tagline, privacy])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 5
        text.setCustomSpacing(10, after: version)

        let hero = NSStackView(views: [icon, text])
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.spacing = 20
        hero.translatesAutoresizingMaskIntoConstraints = false
        return hero
    }

    private func makeQuickStartCard() -> NSView {
        makeCard(
            title: "快速开始",
            symbol: "sparkles",
            rows: [
                ("1", "在任何应用中复制文本、图片或文件。"),
                ("2", "按 ⇧⌘V 打开历史；默认可以直接浏览和预览。"),
                ("3", "选择后按 Return，或双击卡片，粘贴回原来的应用。")
            ]
        )
    }

    private func makeKeyboardCard() -> NSView {
        makeCard(
            title: "键盘快捷键",
            symbol: "keyboard",
            rows: [
                ("⇧⌘V", "打开或关闭剪贴板历史"),
                ("←  →", "在卡片之间移动选择"),
                ("Space", "Quick Look 预览所选内容"),
                ("Tab", "在卡片浏览与搜索框之间切换"),
                ("Return", "把所选内容粘贴到原应用"),
                ("⌘P", "置顶或取消置顶"),
                ("⌘⌫", "删除所选记录"),
                ("⌘1–4", "切换全部、文本、图片、文件"),
                ("Esc", "先清除搜索，再关闭历史窗口")
            ]
        )
    }

    private func makePointerCard() -> NSView {
        makeCard(
            title: "鼠标与触控板",
            symbol: "cursorarrow.click.2",
            rows: [
                ("单击", "选择卡片并复制内容"),
                ("双击", "选择卡片并直接粘贴"),
                ("点搜索框", "进入搜索输入"),
                ("点空白处", "退出搜索，恢复 Space 预览")
            ],
            note: "主屏幕与副屏幕均支持以上操作；触控板点击与鼠标点击行为一致。"
        )
    }

    private func makePrivacyCard() -> NSView {
        makeCard(
            title: "权限、隐私与清理",
            symbol: "hand.raised.fill",
            rows: [
                ("辅助功能", "仅在 Return 或双击粘贴时，用来向原应用发送 ⌘V。"),
                ("本地保存", "历史保存在这台 Mac，不通过网络上传。"),
                ("清空历史", "默认保留置顶记录；按住 ⌥ 打开菜单可清空全部。")
            ],
            note: "权限路径：系统设置 → 隐私与安全性 → 辅助功能。"
        )
    }

    private func makeCard(
        title: String,
        symbol: String,
        rows: [(String, String)],
        note: String? = nil
    ) -> NSView {
        let card = AboutCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let symbolView = NSImageView()
        symbolView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        symbolView.contentTintColor = .controlAccentColor
        symbolView.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 22),
            symbolView.heightAnchor.constraint(equalToConstant: 22)
        ])

        let heading = NSStackView(views: [symbolView, label(title, size: 15, weight: .semibold)])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 8

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.addArrangedSubview(heading)
        stack.setCustomSpacing(13, after: heading)

        for row in rows {
            stack.addArrangedSubview(makeInstructionRow(key: row.0, detail: row.1))
        }

        if let note {
            let noteLabel = label(note, size: 11.5, color: .secondaryLabelColor)
            noteLabel.maximumNumberOfLines = 0
            noteLabel.lineBreakMode = .byWordWrapping
            stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(noteLabel)
            noteLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -17)
        ])
        return card
    }

    private func makeInstructionRow(key: String, detail: String) -> NSView {
        let keycap = KeycapLabel(key)
        keycap.translatesAutoresizingMaskIntoConstraints = false
        keycap.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        let detailLabel = label(detail, size: 12.5)
        detailLabel.maximumNumberOfLines = 0
        detailLabel.lineBreakMode = .byWordWrapping

        let row = NSStackView(views: [keycap, detailLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 13
        detailLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        return row
    }

    private func makeFooter() -> NSView {
        let footer = label("cpsmart · 为 macOS 设计", size: 11, weight: .medium, color: .tertiaryLabelColor)
        footer.alignment = .center
        return footer
    }

    private func loadApplicationIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "CPSmartAppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }

    private var displayVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "开发版"
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return "版本 \(version)"
        }
        return "版本 \(version)（构建 \(build)）"
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class AboutCardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.82).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.42).cgColor
        layer?.borderWidth = 0.5
        layer?.cornerRadius = 14
    }
}

private final class KeycapLabel: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        alignment = .center
        font = .monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        textColor = .labelColor
        wantsLayer = true
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.16).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        layer?.borderWidth = 0.5
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 25).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
