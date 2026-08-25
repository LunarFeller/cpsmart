import AppKit

// MARK: - 外观模式与调色板

/// 外观模式：跟随系统 / 浅色 / 深色。存 UserDefaults，从菜单栏「外观」切换。
enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    static let defaultsKey = "appearanceMode"

    static var current: AppearanceMode {
        get {
            AppearanceMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "")
                ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var isDark: Bool {
        switch self {
        case .dark: return true
        case .light: return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
}

/// 随外观切换的调色板。所有颜色都必须从这里取，不允许另写硬编码颜色。
struct Palette {
    let accent: NSColor
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor
    let cardFill: NSColor
    let cardFillHover: NSColor
    let cardFillSelected: NSColor
    let cardBorder: NSColor
    let panelBorder: NSColor
    let panelTint: NSColor
    let thumbPlaceholder: NSColor
    let typeText: NSColor
    let typeImage: NSColor
    let typeFile: NSColor
}

// MARK: - Theme（尺寸与动效 token + 调色板工厂）

private enum Theme {
    // 面板
    static let panelHeight: CGFloat = 248
    static let panelRadius: CGFloat = 20

    // 卡片
    static let cardSize = NSSize(width: 204, height: 150)
    static let cardRadius: CGFloat = 12
    static let thumbRadius: CGFloat = 8

    // 动效
    static let selectionDuration: TimeInterval = 0.14
    static let entranceDuration: TimeInterval = 0.18
    static let exitDuration: TimeInterval = 0.12

    static func palette(isDark: Bool) -> Palette {
        if isDark {
            let accent = NSColor(srgbRed: 10 / 255, green: 132 / 255, blue: 255 / 255, alpha: 1)
            return Palette(
                accent: accent,
                textPrimary: NSColor.white.withAlphaComponent(0.92),
                textSecondary: NSColor.white.withAlphaComponent(0.55),
                textTertiary: NSColor.white.withAlphaComponent(0.38),
                cardFill: NSColor.white.withAlphaComponent(0.055),
                cardFillHover: NSColor.white.withAlphaComponent(0.09),
                cardFillSelected: accent.withAlphaComponent(0.16),
                cardBorder: NSColor.white.withAlphaComponent(0.10),
                panelBorder: NSColor.white.withAlphaComponent(0.16),
                panelTint: NSColor(srgbRed: 0.055, green: 0.065, blue: 0.085, alpha: 0.78),
                thumbPlaceholder: NSColor.white.withAlphaComponent(0.045),
                typeText: NSColor(srgbRed: 0.35, green: 0.78, blue: 0.98, alpha: 1),
                typeImage: NSColor(srgbRed: 0.72, green: 0.55, blue: 0.98, alpha: 1),
                typeFile: NSColor(srgbRed: 0.98, green: 0.72, blue: 0.32, alpha: 1)
            )
        }
        let accent = NSColor(srgbRed: 0, green: 122 / 255, blue: 1, alpha: 1)
        return Palette(
            accent: accent,
            textPrimary: NSColor.black.withAlphaComponent(0.86),
            textSecondary: NSColor.black.withAlphaComponent(0.56),
            textTertiary: NSColor.black.withAlphaComponent(0.42),
            cardFill: NSColor.black.withAlphaComponent(0.045),
            cardFillHover: NSColor.black.withAlphaComponent(0.075),
            cardFillSelected: accent.withAlphaComponent(0.14),
            cardBorder: NSColor.black.withAlphaComponent(0.10),
            panelBorder: NSColor.black.withAlphaComponent(0.12),
            panelTint: NSColor.white.withAlphaComponent(0.72),
            thumbPlaceholder: NSColor.black.withAlphaComponent(0.05),
            typeText: NSColor(srgbRed: 0.03, green: 0.50, blue: 0.70, alpha: 1),
            typeImage: NSColor(srgbRed: 0.55, green: 0.32, blue: 0.82, alpha: 1),
            typeFile: NSColor(srgbRed: 0.80, green: 0.52, blue: 0.05, alpha: 1)
        )
    }
}

// MARK: - 图片元信息（轻量读取，不解码像素；缩略图本体见 ThumbnailProvider.swift）

private enum ImageMetadata {
    /// 只读图片尺寸，不解码像素，可在主线程调用。
    static func pixelSize(of data: Data) -> NSSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return NSSize(width: width, height: height)
    }
}

// MARK: - 基础控件

private final class FloatingHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class KeyboardCollectionView: NSCollectionView {
    var onMoveLeft: (() -> Void)?
    var onMoveRight: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onDelete: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            onMoveLeft?()
        case 124:
            onMoveRight?()
        case 36, 76:
            onConfirm?()
        case 51, 117:
            if event.modifierFlags.contains(.command) {
                onDelete?()
            } else {
                super.keyDown(with: event)
            }
        case 53:
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class ClickableCardView: NSView {
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

// MARK: - 卡片

private final class HistoryCollectionItem: NSCollectionViewItem {
    var onClick: (() -> Void)? {
        didSet { cardView.onClick = onClick }
    }
    var onDoubleClick: (() -> Void)? {
        didSet { cardView.onDoubleClick = onDoubleClick }
    }

    private let cardView = ClickableCardView()
    private let thumbView = NSView()
    private let dimPill = NSView()
    private let dimLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let sourceIconView = NSImageView()
    private let metaTypeLabel = NSTextField(labelWithString: "")
    private let metaRightLabel = NSTextField(labelWithString: "")

    private var textConstraints: [NSLayoutConstraint] = []
    private var imageConstraints: [NSLayoutConstraint] = []
    private var fileConstraints: [NSLayoutConstraint] = []
    private var metaLeadingDirect: NSLayoutConstraint!
    private var metaLeadingAfterIcon: NSLayoutConstraint!
    private var representedEntryID: UUID?
    private var palette = Theme.palette(isDark: true)

    private var isHovered = false {
        didSet { updateAppearance() }
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override func loadView() {
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = Theme.cardRadius
        cardView.layer?.borderWidth = 1
        cardView.layer?.masksToBounds = false
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.setAccessibilityRole(.button)
        view = cardView

        thumbView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = Theme.thumbRadius
        thumbView.layer?.masksToBounds = true
        thumbView.layer?.contentsGravity = .resizeAspectFill

        dimPill.translatesAutoresizingMaskIntoConstraints = false
        dimPill.wantsLayer = true
        dimPill.layer?.cornerRadius = 6
        dimPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor

        dimLabel.translatesAutoresizingMaskIntoConstraints = false
        dimLabel.font = .systemFont(ofSize: 9, weight: .medium)
        dimLabel.textColor = NSColor.white.withAlphaComponent(0.92)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 6

        metaTypeLabel.translatesAutoresizingMaskIntoConstraints = false
        metaTypeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        metaTypeLabel.lineBreakMode = .byTruncatingTail

        metaRightLabel.translatesAutoresizingMaskIntoConstraints = false
        metaRightLabel.font = .systemFont(ofSize: 10, weight: .medium)
        metaRightLabel.alignment = .right

        sourceIconView.translatesAutoresizingMaskIntoConstraints = false
        sourceIconView.imageScaling = .scaleProportionallyUpOrDown
        sourceIconView.isHidden = true

        dimPill.addSubview(dimLabel)
        thumbView.addSubview(dimPill)
        cardView.addSubview(thumbView)
        cardView.addSubview(iconView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(sourceIconView)
        cardView.addSubview(metaTypeLabel)
        cardView.addSubview(metaRightLabel)

        metaLeadingDirect = metaTypeLabel.leadingAnchor.constraint(
            equalTo: cardView.leadingAnchor, constant: 12
        )
        metaLeadingAfterIcon = metaTypeLabel.leadingAnchor.constraint(
            equalTo: sourceIconView.trailingAnchor, constant: 5
        )

        // 底部元信息行（所有类型共用）：来源应用图标 + 类型 · 详情，右侧相对时间
        NSLayoutConstraint.activate([
            metaLeadingDirect,

            sourceIconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            sourceIconView.centerYAnchor.constraint(equalTo: metaTypeLabel.centerYAnchor),
            sourceIconView.widthAnchor.constraint(equalToConstant: 11),
            sourceIconView.heightAnchor.constraint(equalToConstant: 11),

            metaTypeLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -9),

            metaRightLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            metaRightLabel.centerYAnchor.constraint(equalTo: metaTypeLabel.centerYAnchor),
            metaRightLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: metaTypeLabel.trailingAnchor, constant: 8
            ),

            dimLabel.leadingAnchor.constraint(equalTo: dimPill.leadingAnchor, constant: 6),
            dimLabel.trailingAnchor.constraint(equalTo: dimPill.trailingAnchor, constant: -6),
            dimLabel.topAnchor.constraint(equalTo: dimPill.topAnchor, constant: 2),
            dimLabel.bottomAnchor.constraint(equalTo: dimPill.bottomAnchor, constant: -2),

            dimPill.trailingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: -6),
            dimPill.bottomAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: -6)
        ])

        // 文本卡：多行预览占据内容区
        textConstraints = [
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 11),
            titleLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: metaTypeLabel.topAnchor, constant: -6
            )
        ]

        // 图片卡：缩略图铺满内容区
        imageConstraints = [
            thumbView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            thumbView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            thumbView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            thumbView.bottomAnchor.constraint(equalTo: metaTypeLabel.topAnchor, constant: -6)
        ]

        // 文件卡：大图标居中 + 文件名
        fileConstraints = [
            iconView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 38),
            iconView.heightAnchor.constraint(equalToConstant: 38),

            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: metaTypeLabel.topAnchor, constant: -4
            )
        ]

        cardView.onHoverChanged = { [weak self] hovered in
            self?.isHovered = hovered
        }

        updateAppearance()
    }

    func configure(with entry: ClipboardEntry, thumbnails: ThumbnailProvider, palette: Palette) {
        self.palette = palette
        representedEntryID = entry.id
        NSLayoutConstraint.deactivate(textConstraints + imageConstraints + fileConstraints)
        thumbView.layer?.contents = nil
        thumbView.layer?.backgroundColor = palette.thumbPlaceholder.cgColor
        thumbView.isHidden = true
        dimPill.isHidden = true
        iconView.isHidden = true
        titleLabel.isHidden = true
        titleLabel.textColor = palette.textPrimary
        metaRightLabel.textColor = palette.textTertiary

        metaRightLabel.stringValue = Self.relativeDate.string(for: entry.createdAt) ?? "刚刚"
        configureSourceApp(entry)

        switch entry.payload {
        case .text(let text):
            titleLabel.isHidden = false
            titleLabel.alignment = .left
            titleLabel.font = .systemFont(ofSize: 12)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.stringValue = Self.preview(text)
            metaTypeLabel.stringValue = "文本 · \(text.count) 字符"
            metaTypeLabel.textColor = palette.typeText
            NSLayoutConstraint.activate(textConstraints)

        case .image(let data, _):
            thumbView.isHidden = false
            metaTypeLabel.stringValue = "图片 · \(Self.byteCount.string(fromByteCount: Int64(data.count)))"
            metaTypeLabel.textColor = palette.typeImage
            if let size = ImageMetadata.pixelSize(of: data) {
                dimLabel.stringValue = "\(Int(size.width)) × \(Int(size.height))"
                dimPill.isHidden = false
            }
            NSLayoutConstraint.activate(imageConstraints)
            let entryID = entry.id
            thumbnails.thumbnail(for: entry) { [weak self] image in
                guard let self, self.representedEntryID == entryID, let image else { return }
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.15
                self.thumbView.layer?.add(fade, forKey: "thumbnailFade")
                self.thumbView.layer?.contents = image
            }

        case .files(let paths):
            iconView.isHidden = false
            titleLabel.isHidden = false
            iconView.image = NSWorkspace.shared.icon(forFile: paths.first ?? "")
            titleLabel.alignment = .center
            titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
            titleLabel.lineBreakMode = .byTruncatingMiddle
            titleLabel.maximumNumberOfLines = 2
            if paths.count == 1 {
                titleLabel.stringValue = URL(fileURLWithPath: paths[0]).lastPathComponent
                metaTypeLabel.stringValue = "文件"
            } else {
                titleLabel.stringValue = paths
                    .map { URL(fileURLWithPath: $0).lastPathComponent }
                    .joined(separator: "、")
                metaTypeLabel.stringValue = "\(paths.count) 个文件"
            }
            metaTypeLabel.textColor = palette.typeFile
            NSLayoutConstraint.activate(fileConstraints)
        }

        cardView.setAccessibilityLabel(titleLabel.stringValue)
    }

    /// 元信息行左侧展示来源应用图标；旧记录没有来源信息时不占位。
    private func configureSourceApp(_ entry: ClipboardEntry) {
        guard let bundleID = entry.sourceAppBundleID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            sourceIconView.isHidden = true
            sourceIconView.image = nil
            metaLeadingAfterIcon.isActive = false
            metaLeadingDirect.isActive = true
            return
        }
        sourceIconView.image = NSWorkspace.shared.icon(forFile: appURL.path)
        sourceIconView.toolTip = entry.sourceAppName.map { "来自 \($0)" }
        sourceIconView.isHidden = false
        metaLeadingDirect.isActive = false
        metaLeadingAfterIcon.isActive = true
    }

    private func updateAppearance() {
        guard isViewLoaded, let layer = cardView.layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(Theme.selectionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        if isSelected {
            layer.borderWidth = 1.5
            layer.borderColor = palette.accent.cgColor
            layer.backgroundColor = palette.cardFillSelected.cgColor
            layer.shadowOpacity = 0.45
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: -4)
            layer.transform = CATransform3DMakeScale(1.03, 1.03, 1)
        } else {
            layer.borderWidth = 1
            layer.borderColor = palette.cardBorder.cgColor
            layer.backgroundColor = (isHovered ? palette.cardFillHover : palette.cardFill).cgColor
            layer.shadowOpacity = 0.22
            layer.shadowRadius = 5
            layer.shadowOffset = CGSize(width: 0, height: -2)
            layer.transform = CATransform3DIdentity
        }
        CATransaction.commit()
    }

    private static func preview(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: "\n")
    }

    private static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let byteCount: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

// MARK: - 类型筛选

private enum TypeFilter: Int {
    case all = 0
    case text
    case image
    case files

    func matches(_ entry: ClipboardEntry) -> Bool {
        switch (self, entry.payload) {
        case (.all, _),
             (.text, .text),
             (.image, .image),
             (.files, .files):
            return true
        default:
            return false
        }
    }
}

// MARK: - 浮窗控制器

final class HistoryWindowController: NSWindowController,
    NSCollectionViewDataSource,
    NSCollectionViewDelegate,
    NSSearchFieldDelegate,
    NSWindowDelegate
{
    var onChoose: ((ClipboardEntry) -> Void)?
    var onPaste: ((NSRunningApplication?) -> PasteStartResult)?
    var onDelete: ((ClipboardEntry) -> Void)?

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("HistoryCollectionItem")
    private let collectionView = KeyboardCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private let thumbnailProvider = ThumbnailProvider()
    private let searchField = NSSearchField()
    private var filterControl: NSSegmentedControl!
    private let titleLabel = NSTextField(labelWithString: "cpsmart")
    private let countLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")
    private var effectView: NSVisualEffectView!
    private var tintView: NSView!

    private var palette = Theme.palette(isDark: true)
    private var allEntries: [ClipboardEntry] = []
    private var visibleEntries: [ClipboardEntry] = []
    private var query = ""
    private var typeFilter: TypeFilter = .all
    private var selectedIndex = 0
    private var previousApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?
    private var suppressSelectionCallback = false
    private var keyboardMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var systemThemeObserver: NSObjectProtocol?
    private var isDismissing = false

    init() {
        let panel = FloatingHistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: Theme.panelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "cpsmart 剪贴板历史"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        super.init(window: panel)
        panel.delegate = self
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            self?.rememberExternalApplication(application)
        }
        // 系统深浅色切换时，「跟随系统」模式要跟着变
        systemThemeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearanceMode()
        }
        buildInterface()
        applyAppearanceMode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeKeyboardMonitor()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let systemThemeObserver {
            DistributedNotificationCenter.default().removeObserver(systemThemeObserver)
        }
    }

    /// 应用外观模式；传 nil 时读取当前设置。菜单切换或系统主题变化时调用。
    func applyAppearanceMode(_ mode: AppearanceMode? = nil) {
        let isDark = (mode ?? AppearanceMode.current).isDark
        palette = Theme.palette(isDark: isDark)

        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        window?.appearance = appearance
        effectView?.appearance = appearance
        tintView?.layer?.backgroundColor = palette.panelTint.cgColor
        effectView?.layer?.borderColor = palette.panelBorder.cgColor

        titleLabel.textColor = palette.textPrimary
        countLabel.textColor = palette.textTertiary
        statusLabel.textColor = palette.textSecondary
        hintLabel.textColor = palette.textTertiary
        emptyLabel.textColor = palette.textTertiary

        // 卡片颜色由各 item 在 configure 时按 palette 重写
        reloadCollection(selecting: visibleEntries.isEmpty ? nil : selectedIndex, notify: false)
    }

    func show(entries: [ClipboardEntry]) {
        if window?.isVisible == true {
            if !isDismissing {
                dismiss(restorePreviousApplication: true)
            }
            return
        }

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if isExternalApplication(frontmostApplication) {
            previousApplication = frontmostApplication
            rememberExternalApplication(frontmostApplication)
        } else {
            previousApplication = lastExternalApplication
        }

        allEntries = entries
        query = ""
        searchField.stringValue = ""
        typeFilter = .all
        filterControl.selectedSegment = 0
        selectedIndex = 0

        guard let window else { return }
        let finalFrame = targetFrame()
        // 先摆到最终位置完成布局与数据加载，再偏移一点做入场动画。
        window.setFrame(finalFrame, display: false)
        updateContentInsets()
        refilter(fallbackIndex: 0)

        installKeyboardMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window.alphaValue = 0
        window.setFrame(finalFrame.offsetBy(dx: 0, dy: -10), display: false)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.entranceDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 1
        }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.makeFirstResponder(self.searchField)
        }
    }

    func refresh(entries: [ClipboardEntry], selectingEntryID: UUID? = nil) {
        // 普通刷新保留当前选择；剪贴板捕获刷新则聚焦刚加入的记录，
        // 避免旧选择随着新记录插入不断右移并把最新内容留在屏幕左侧之外。
        let selectedID = selectingEntryID ?? (
            visibleEntries.indices.contains(selectedIndex)
                ? visibleEntries[selectedIndex].id
                : nil
        )
        allEntries = entries
        refilter(
            selectingID: selectedID,
            fallbackIndex: selectingEntryID == nil ? selectedIndex : 0
        )
    }

    // MARK: 界面搭建

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Theme.panelRadius
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.5
        contentView.addSubview(effectView)

        // 色调罩层：盖在毛玻璃上保证深浅两种模式在任何壁纸下基调一致，
        // 具体颜色由 applyAppearanceMode() 按 palette 设置
        tintView = NSView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        effectView.addSubview(tintView)
        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: effectView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        // 头部：贴边布局（不要把宽度约束写死成某个值——完全确定的约束链会让
        // AppKit 算出固定的 fittingSize 并在 layout 时把窗口"回正"到那个尺寸，
        // 全宽浮窗必须让约束欠定，由窗口框架驱动布局）
        let headerContainer = NSView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(headerContainer)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索剪贴板历史"
        searchField.font = .systemFont(ofSize: 12)
        searchField.delegate = self

        filterControl = NSSegmentedControl(
            labels: ["全部", "文本", "图片", "文件"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(filterChanged(_:))
        )
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        filterControl.controlSize = .small
        filterControl.selectedSegment = 0

        statusLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        headerContainer.addSubview(titleLabel)
        headerContainer.addSubview(countLabel)
        headerContainer.addSubview(searchField)
        headerContainer.addSubview(filterControl)
        headerContainer.addSubview(statusLabel)

        // 卡片流
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // 不显示滚动条：自定义 InvisibleScroller 会把 scrollerStyle 重置为 legacy 并占用布局高度
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.drawsBackground = false

        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = Theme.cardSize
        flowLayout.minimumInteritemSpacing = 10
        flowLayout.minimumLineSpacing = 10
        flowLayout.sectionInset = NSEdgeInsets(top: 4, left: 24, bottom: 4, right: 24)

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            HistoryCollectionItem.self,
            forItemWithIdentifier: Self.itemIdentifier
        )
        collectionView.onMoveLeft = { [weak self] in self?.moveSelection(by: -1) }
        collectionView.onMoveRight = { [weak self] in self?.moveSelection(by: 1) }
        collectionView.onConfirm = { [weak self] in self?.confirmAndPaste() }
        collectionView.onDelete = { [weak self] in self?.deleteSelection() }
        collectionView.onEscape = { [weak self] in
            self?.dismiss(restorePreviousApplication: true)
        }
        scrollView.documentView = collectionView

        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 12.5)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.alignment = .center
        hintLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(scrollView)
        effectView.addSubview(emptyLabel)
        effectView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            headerContainer.leadingAnchor.constraint(
                equalTo: effectView.leadingAnchor, constant: 24
            ),
            headerContainer.trailingAnchor.constraint(
                equalTo: effectView.trailingAnchor, constant: -24
            ),
            headerContainer.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 14),
            headerContainer.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),

            searchField.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 16),
            searchField.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 240),

            statusLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            filterControl.trailingAnchor.constraint(
                equalTo: statusLabel.leadingAnchor, constant: -14
            ),
            filterControl.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            filterControl.leadingAnchor.constraint(
                greaterThanOrEqualTo: searchField.trailingAnchor, constant: 14
            ),

            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 12),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            hintLabel.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            hintLabel.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -10)
        ])

        updateHintLabel()
    }

    // MARK: 布局与定位

    private func targetFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return NSRect(x: 0, y: 0, width: 960, height: Theme.panelHeight)
        }
        return NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: Theme.panelHeight
        )
    }

    private func updateContentInsets() {
        // 卡片流与头部一样通栏贴边，保持左缘对齐
        flowLayout.sectionInset = NSEdgeInsets(top: 4, left: 24, bottom: 4, right: 24)
        flowLayout.invalidateLayout()
    }

    func windowDidResize(_ notification: Notification) {
        updateContentInsets()
    }

    // MARK: 过滤

    private func refilter(selectingID id: UUID? = nil, fallbackIndex: Int) {
        visibleEntries = SearchFilter.filter(allEntries, query: query)
            .filter { typeFilter.matches($0) }

        let index: Int?
        if let id, let match = visibleEntries.firstIndex(where: { $0.id == id }) {
            index = match
        } else if !visibleEntries.isEmpty {
            index = min(fallbackIndex, visibleEntries.count - 1)
        } else {
            index = nil
        }
        reloadCollection(selecting: index, notify: false)
    }

    private func reloadCollection(selecting index: Int?, notify: Bool) {
        suppressSelectionCallback = true
        collectionView.reloadData()
        updateHeaderState()

        if let index, visibleEntries.indices.contains(index) {
            selectedIndex = index
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.layoutSubtreeIfNeeded()
            collectionView.selectionIndexPaths = [indexPath]
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredHorizontally)
        } else {
            selectedIndex = 0
            collectionView.selectionIndexPaths = []
        }
        suppressSelectionCallback = false
        if notify, let index, visibleEntries.indices.contains(index) {
            chooseEntry(at: index)
        } else {
            statusLabel.stringValue = ""
        }
    }

    private func updateHeaderState() {
        let isFiltering = !query.isEmpty || typeFilter != .all
        countLabel.stringValue = isFiltering
            ? "匹配 \(visibleEntries.count) / \(allEntries.count)"
            : "\(allEntries.count) 项"

        if allEntries.isEmpty {
            emptyLabel.stringValue = "还没有记录 · 先复制一些文本、图片或文件"
            emptyLabel.isHidden = false
        } else if visibleEntries.isEmpty {
            emptyLabel.stringValue = query.isEmpty
                ? "该类型下没有记录"
                : "没有匹配「\(query)」的记录"
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
        updateHintLabel()
    }

    private func updateHintLabel() {
        hintLabel.stringValue = query.isEmpty
            ? "← → 选择 · ⏎ 粘贴 · ⌘⌫ 删除 · ⌘1–4 筛选 · Esc 关闭"
            : "输入继续过滤 · ⏎ 粘贴所选 · Esc 清除搜索"
    }

    // MARK: 选择与动作

    private func moveSelection(by offset: Int) {
        guard !visibleEntries.isEmpty else { return }
        let newIndex = min(max(selectedIndex + offset, 0), visibleEntries.count - 1)
        selectAndChoose(index: newIndex, notifyWhenUnchanged: true)
    }

    private func selectAndChoose(index: Int, notifyWhenUnchanged: Bool) {
        guard visibleEntries.indices.contains(index) else { return }
        let selectionChanged = selectedIndex != index
        guard selectionChanged || notifyWhenUnchanged else { return }
        selectedIndex = index
        suppressSelectionCallback = true
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.selectionIndexPaths = [indexPath]
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredHorizontally)
        suppressSelectionCallback = false
        chooseEntry(at: index)
    }

    private func chooseEntry(at index: Int) {
        guard visibleEntries.indices.contains(index) else { return }
        let entry = visibleEntries[index]
        onChoose?(entry)
        statusLabel.stringValue = "已选择 \(index + 1) / \(visibleEntries.count)"
        statusLabel.textColor = palette.accent
    }

    private func confirmAndPaste() {
        guard visibleEntries.indices.contains(selectedIndex) else { return }
        onChoose?(visibleEntries[selectedIndex])
        let result = onPaste?(previousApplication) ?? .targetUnavailable
        switch result {
        case .started:
            dismiss(restorePreviousApplication: false)
        case .permissionRequired:
            statusLabel.stringValue = "当前版本的权限未生效，请删除系统设置中的 cpsmart 后重新添加"
            statusLabel.textColor = .systemOrange
            NSSound.beep()
        case .targetUnavailable:
            statusLabel.stringValue = "无法找到刚才使用的应用，请关闭浮窗后重试"
            statusLabel.textColor = .systemOrange
            NSSound.beep()
        }
    }

    private func deleteSelection() {
        guard visibleEntries.indices.contains(selectedIndex) else { return }
        onDelete?(visibleEntries[selectedIndex])
    }

    private func clearSearch() {
        searchField.stringValue = ""
        query = ""
        refilter(fallbackIndex: selectedIndex)
        statusLabel.stringValue = ""
    }

    // MARK: 搜索与筛选

    #if DEBUG
    /// 开发用：演示模式下预填搜索词，便于截图验证过滤渲染。
    func applyDemoQuery(_ demoQuery: String) {
        searchField.stringValue = demoQuery
        query = demoQuery
        refilter(fallbackIndex: 0)
    }
    #endif

    func controlTextDidChange(_ notification: Notification) {
        query = searchField.stringValue
        refilter(fallbackIndex: 0)
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        typeFilter = TypeFilter(rawValue: sender.selectedSegment) ?? .all
        refilter(fallbackIndex: 0)
        window?.makeFirstResponder(searchField)
    }

    // MARK: 关闭

    private func dismiss(restorePreviousApplication: Bool) {
        guard let window, window.isVisible, !isDismissing else { return }
        isDismissing = true
        removeKeyboardMonitor()
        thumbnailProvider.cancelAll()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Theme.exitDuration
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak window] in
            guard let self else { return }
            window?.orderOut(nil)
            window?.alphaValue = 1
            self.isDismissing = false
            if restorePreviousApplication,
               let previousApplication = self.previousApplication,
               previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApplication.activate(options: [.activateIgnoringOtherApps])
            }
            self.previousApplication = nil
        })
    }

    // MARK: 键盘

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self,
                  self.window?.isVisible == true,
                  self.handleKeyboardEvent(event) else {
                return event
            }
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }

    private func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        // ⌘1–⌘4 切换类型筛选
        if event.modifierFlags.contains(.command), (18...21).contains(event.keyCode) {
            filterControl.selectedSegment = Int(event.keyCode) - 18
            filterChanged(filterControl)
            return true
        }

        switch event.keyCode {
        case 123:
            moveSelection(by: -1)
        case 124:
            moveSelection(by: 1)
        case 36, 76:
            confirmAndPaste()
        case 51, 117:
            // 删除统一走 ⌘⌫（同 Finder）：搜索时退格要留给文本编辑，
            // 连按退格清空搜索词后若继续删记录容易误删
            if event.modifierFlags.contains(.command) {
                deleteSelection()
            } else {
                return false
            }
        case 53:
            // Esc 优先清除搜索，再按一次才关闭
            if !query.isEmpty {
                clearSearch()
            } else {
                dismiss(restorePreviousApplication: true)
            }
        default:
            return false
        }
        return true
    }

    // MARK: 前台应用追踪

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard isExternalApplication(application) else { return }
        lastExternalApplication = application
    }

    private func isExternalApplication(_ application: NSRunningApplication?) -> Bool {
        guard let application, !application.isTerminated else { return false }
        return application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    // MARK: NSCollectionViewDataSource / Delegate

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        visibleEntries.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: Self.itemIdentifier,
            for: indexPath
        ) as! HistoryCollectionItem
        item.configure(
            with: visibleEntries[indexPath.item],
            thumbnails: thumbnailProvider,
            palette: palette
        )
        item.onClick = { [weak self] in
            self?.selectAndChoose(index: indexPath.item, notifyWhenUnchanged: true)
        }
        item.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.selectAndChoose(index: indexPath.item, notifyWhenUnchanged: false)
            self.confirmAndPaste()
        }
        return item
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard !suppressSelectionCallback, let indexPath = indexPaths.first else { return }
        selectedIndex = indexPath.item
        chooseEntry(at: indexPath.item)
    }
}
