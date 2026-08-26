import AppKit
import Quartz

private extension NSRect {
    func approximatelyEquals(_ other: NSRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

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

// MARK: - Theme（尺寸与动效 token）

private enum Theme {
    // 面板
    static let panelHeight: CGFloat = 248
    static let panelRadius = AppVisualTheme.panelRadius

    // 卡片
    static let cardSize = NSSize(width: 204, height: 150)
    static let cardRadius = AppVisualTheme.cardRadius
    static let thumbRadius: CGFloat = 8

    // 动效
    static let selectionDuration: TimeInterval = 0.14
    static let entranceDuration: TimeInterval = 0.18
    static let exitDuration: TimeInterval = 0.12

}

// MARK: - 图片元信息（轻量读取，不解码像素；缩略图本体见 ThumbnailProvider.swift）

enum ImageMetadata {
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
    var onBackgroundClick: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard indexPathForItem(at: point) != nil else {
            onBackgroundClick?()
            return
        }
        super.mouseDown(with: event)
    }
}

private struct PinboardDragDescriptor {
    let entryID: UUID
    let sourcePinboardID: UUID?

    static let pasteboardType = NSPasteboard.PasteboardType("com.cpsmart.pinboard-entry")

    func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        var value = entryID.uuidString
        if let sourcePinboardID {
            value += "|\(sourcePinboardID.uuidString)"
        }
        item.setString(value, forType: Self.pasteboardType)
        return item
    }

    static func read(from pasteboard: NSPasteboard) -> PinboardDragDescriptor? {
        guard let rawValue = pasteboard.string(forType: pasteboardType) else { return nil }
        let parts = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
        guard let entryID = UUID(uuidString: parts[0]) else { return nil }
        let sourcePinboardID = parts.count == 2 ? UUID(uuidString: parts[1]) : nil
        return PinboardDragDescriptor(entryID: entryID, sourcePinboardID: sourcePinboardID)
    }
}

private final class PinboardTabButton: NSButton {
    var onAcceptHistoryEntry: ((UUID) -> Void)? {
        didSet {
            if onAcceptHistoryEntry != nil {
                registerForDraggedTypes([PinboardDragDescriptor.pasteboardType])
            }
        }
    }

    var dropHighlightColor: NSColor = .controlAccentColor

    private var palette = AppVisualTheme.palette(isDark: true)
    private var isSelectedTab = false
    private var tintColor: NSColor?
    private var isHovered = false
    private var isDropHighlighted = false
    private var hoverTrackingArea: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 18
        size.height = 24
        return size
    }

    /// 无边框按钮默认把内容贴左绘制；背景、边框、内容全部在 draw 里手动居中绘制，
    /// 避免依赖 updateLayer 的调用时机。
    override func draw(_ dirtyRect: NSRect) {
        let fill: NSColor
        if isSelectedTab {
            fill = (tintColor ?? palette.accent).withAlphaComponent(0.18)
        } else if isHovered {
            fill = palette.cardFillHover
        } else {
            fill = palette.cardFill
        }
        let pill = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        fill.setFill()
        pill.fill()
        if isDropHighlighted {
            dropHighlightColor.setStroke()
            pill.lineWidth = 2
            pill.stroke()
        }

        guard let cell else { return }
        let contentSize = cell.cellSize
        guard contentSize.width > 0, contentSize.height > 0,
              contentSize.width < bounds.width else {
            super.draw(dirtyRect)
            return
        }
        let centered = NSRect(
            x: (bounds.width - contentSize.width) / 2,
            y: (bounds.height - contentSize.height) / 2,
            width: contentSize.width,
            height: contentSize.height
        )
        cell.draw(withFrame: centered, in: self)
    }

    /// 扁平药丸样式：未选中只有浅底，选中用收藏板颜色淡填，不再使用系统边框。
    func applyStyle(palette: Palette, selected: Bool, tint: NSColor?) {
        self.palette = palette
        isSelectedTab = selected
        tintColor = tint
        isBordered = false
        wantsLayer = true
        let weight: NSFont.Weight = selected ? .semibold : .medium
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: weight),
                .foregroundColor: selected ? palette.textPrimary : palette.textSecondary
            ]
        )
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let descriptor = PinboardDragDescriptor.read(from: sender.draggingPasteboard),
              descriptor.sourcePinboardID == nil,
              onAcceptHistoryEntry != nil else { return [] }
        setDropHighlighted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let descriptor = PinboardDragDescriptor.read(from: sender.draggingPasteboard),
              descriptor.sourcePinboardID == nil,
              onAcceptHistoryEntry != nil else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropHighlighted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        PinboardDragDescriptor.read(from: sender.draggingPasteboard)?.sourcePinboardID == nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setDropHighlighted(false) }
        guard let descriptor = PinboardDragDescriptor.read(from: sender.draggingPasteboard),
              descriptor.sourcePinboardID == nil,
              let onAcceptHistoryEntry else { return false }
        onAcceptHistoryEntry(descriptor.entryID)
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        // 拖拽被 Esc 取消时不会触发 draggingExited，需要兜底清理高亮。
        setDropHighlighted(false)
    }

    private func setDropHighlighted(_ isHighlighted: Bool) {
        isDropHighlighted = isHighlighted
        needsDisplay = true
    }
}

/// 新建收藏板用的色点行选择器：直接点选颜色，选中项带描边圈。
private final class PinboardColorPickerView: NSView {
    private(set) var selectedIndex: Int = 0 {
        didSet { updateSelection() }
    }

    private var buttons: [NSButton] = []

    init(colors: [NSColor], names: [String]) {
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 10
        for (index, color) in colors.enumerated() {
            let button = NSButton(
                image: Self.dotImage(color, diameter: 16),
                target: self,
                action: #selector(choose(_:))
            )
            button.tag = index
            button.isBordered = false
            button.wantsLayer = true
            button.toolTip = index < names.count ? names[index] : nil
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22)
            ])
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 22)
        ])
        updateSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(index: Int) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            button.layer?.cornerRadius = 11
            button.layer?.borderWidth = selected ? 2 : 0
            button.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.55).cgColor
        }
    }

    @objc private func choose(_ sender: NSButton) {
        selectedIndex = sender.tag
    }

    private static func dotImage(_ color: NSColor, diameter: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

private final class ClickableCardView: NSView {
    var onClick: ((Int) -> Void)?
    var onDrag: ((NSEvent, NSView) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var didBeginDrag = false

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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// AppKit 传给 hitTest 的点属于父视图坐标系，必须先转换成卡片本地坐标。
    /// 直接与 bounds 比较会让横向滚动后的卡片命中区域整体错位。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        didBeginDrag = false
        window?.makeKey()
        onClick?(event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDrag else { return }
        didBeginDrag = true
        onDrag?(event, self)
    }

    override func mouseUp(with event: NSEvent) {
        didBeginDrag = false
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?(1)
        return true
    }
}

// MARK: - 卡片

private final class HistoryCollectionItem: NSCollectionViewItem {
    var onClick: ((Int) -> Void)? {
        didSet { cardView.onClick = onClick }
    }

    var onDrag: ((NSEvent, NSView) -> Void)? {
        didSet { cardView.onDrag = onDrag }
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
    private let pinImageView = NSImageView()

    private var textConstraints: [NSLayoutConstraint] = []
    private var imageConstraints: [NSLayoutConstraint] = []
    private var fileConstraints: [NSLayoutConstraint] = []
    private var metaLeadingDirect: NSLayoutConstraint!
    private var metaLeadingAfterIcon: NSLayoutConstraint!
    private var representedEntryID: UUID?
    private var palette = AppVisualTheme.palette(isDark: true)

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
        titleLabel.wantsLayer = true
        titleLabel.layer?.masksToBounds = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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

        pinImageView.translatesAutoresizingMaskIntoConstraints = false
        pinImageView.image = NSImage(
            systemSymbolName: "pin.fill",
            accessibilityDescription: "已置顶"
        )
        pinImageView.imageScaling = .scaleProportionallyUpOrDown
        pinImageView.isHidden = true

        dimPill.addSubview(dimLabel)
        thumbView.addSubview(dimPill)
        cardView.addSubview(thumbView)
        cardView.addSubview(iconView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(sourceIconView)
        cardView.addSubview(metaTypeLabel)
        cardView.addSubview(metaRightLabel)
        cardView.addSubview(pinImageView)

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
            dimPill.bottomAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: -6),

            // 置顶标记固定在卡片右上角
            pinImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            pinImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -9),
            pinImageView.widthAnchor.constraint(equalToConstant: 10),
            pinImageView.heightAnchor.constraint(equalToConstant: 10)
        ])

        // 文本卡：多行预览占据内容区
        textConstraints = [
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            titleLabel.widthAnchor.constraint(
                lessThanOrEqualToConstant: Theme.cardSize.width - 24
            ),
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
        pinImageView.isHidden = entry.isPinned != true
        pinImageView.contentTintColor = palette.accent
        configureSourceApp(entry)

        switch entry.payload {
        case .text(let text):
            titleLabel.isHidden = false
            titleLabel.alignment = .left
            titleLabel.font = .systemFont(ofSize: 12)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.maximumNumberOfLines = 6
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
        let normalized = String(text.prefix(2_000))
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: "\n")

        let maximumCharacterCount = 360
        guard normalized.count > maximumCharacterCount else { return normalized }
        return String(normalized.prefix(maximumCharacterCount)) + "…"
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
    NSWindowDelegate,
    QLPreviewPanelDataSource,
    QLPreviewPanelDelegate,
    NSDraggingSource
{
    var onChoose: ((ClipboardEntry) -> Void)?
    var onPaste: ((NSRunningApplication?) -> PasteStartResult)?
    var onDelete: ((ClipboardEntry) -> Void)?
    var onTogglePin: ((ClipboardEntry) -> Void)?
    var onCreatePinboard: ((String, PinboardColor) -> Pinboard?)?
    var onRenamePinboard: ((UUID, String) -> Void)?
    var onSetPinboardColor: ((UUID, PinboardColor) -> Void)?
    var onDeletePinboard: ((UUID) -> Void)?
    var onAddToPinboard: ((ClipboardEntry, UUID) -> Void)?
    var onRemoveFromPinboard: ((ClipboardEntry, UUID) -> Void)?
    var onMovePinboardEntry: ((UUID, UUID, Int) -> Void)?

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("HistoryCollectionItem")
    private let collectionView = KeyboardCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private let thumbnailProvider = ThumbnailProvider()
    private let adaptivePreviewController = AdaptivePreviewController()
    private let shortcutStore: ShortcutStore
    private let shortcutMatcher: ShortcutMatcher
    private let searchField = NSSearchField()
    private var filterControl: NSSegmentedControl!
    private let favoriteButton = NSButton()
    private let boardStackView = NSStackView()
    private let countLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")
    private var effectView: NSVisualEffectView!
    private var tintView: NSView!

    private var palette = AppVisualTheme.palette(isDark: true)
    private var historyEntries: [ClipboardEntry] = []
    private var pinboards: [Pinboard] = []
    private var selectedPinboardID: UUID?
    private var allEntries: [ClipboardEntry] = []
    private var visibleEntries: [ClipboardEntry] = []
    private var query = ""
    private var typeFilter: TypeFilter = .all
    private var selectedIndex = 0
    private var previousApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?
    private var suppressSelectionCallback = false
    private var keyboardMonitor: Any?
    private var mouseMonitor: Any?
    private var quickLookPreviewURL: URL?
    private var isPositioningQuickLookPanel = false
    private var activationObserver: NSObjectProtocol?
    private var systemThemeObserver: NSObjectProtocol?
    private var shortcutObserver: NSObjectProtocol?
    private var isDismissing = false
    private var dismissalGeneration = 0

    init(shortcutStore: ShortcutStore) {
        self.shortcutStore = shortcutStore
        shortcutMatcher = ShortcutMatcher(store: shortcutStore)
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
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.didChangeNotification,
            object: shortcutStore,
            queue: .main
        ) { [weak self] _ in
            self?.updateHintLabel()
        }
        buildInterface()
        applyAppearanceMode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeKeyboardMonitor()
        adaptivePreviewController.close()
        cleanupQuickLookTempFiles()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let systemThemeObserver {
            DistributedNotificationCenter.default().removeObserver(systemThemeObserver)
        }
        if let shortcutObserver {
            NotificationCenter.default.removeObserver(shortcutObserver)
        }
    }

    /// 应用外观模式；传 nil 时读取当前设置。菜单切换或系统主题变化时调用。
    func applyAppearanceMode(_ mode: AppearanceMode? = nil) {
        let isDark = (mode ?? AppearanceMode.current).isDark
        palette = AppVisualTheme.palette(isDark: isDark)

        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        window?.appearance = appearance
        effectView?.appearance = appearance
        tintView?.layer?.backgroundColor = palette.panelTint.cgColor
        effectView?.layer?.borderColor = palette.panelBorder.cgColor

        countLabel.textColor = palette.textTertiary
        statusLabel.textColor = palette.textSecondary
        hintLabel.textColor = palette.textTertiary
        emptyLabel.textColor = palette.textTertiary

        // 卡片颜色由各 item 在 configure 时按 palette 重写
        rebuildPinboardTabs()
        reloadCollection(selecting: visibleEntries.isEmpty ? nil : selectedIndex, notify: false)
    }

    func show(entries: [ClipboardEntry], pinboards: [Pinboard] = []) {
        if window?.isVisible == true {
            if isDismissing {
                // 退场动画进行中：作废旧动画的完成回调并立即复位，
                // 避免全局快捷键在 0.12s 动画窗口内被吞掉。
                dismissalGeneration += 1
                window?.orderOut(nil)
                window?.alphaValue = 1
                isDismissing = false
            } else {
                dismiss(restorePreviousApplication: true)
                return
            }
        }

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if isExternalApplication(frontmostApplication) {
            previousApplication = frontmostApplication
            rememberExternalApplication(frontmostApplication)
        } else {
            previousApplication = lastExternalApplication
        }

        historyEntries = entries
        self.pinboards = pinboards
        selectedPinboardID = nil
        allEntries = entries
        query = ""
        searchField.stringValue = ""
        searchField.placeholderString = "搜索剪贴板历史"
        typeFilter = .all
        filterControl.selectedSegment = 0
        selectedIndex = 0
        rebuildPinboardTabs()

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
            window.makeFirstResponder(self.collectionView)
            self.updateHintLabel()
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
        historyEntries = entries
        guard selectedPinboardID == nil else {
            rebuildPinboardTabs()
            return
        }
        allEntries = entries
        refilter(
            selectingID: selectedID,
            fallbackIndex: selectingEntryID == nil ? selectedIndex : 0
        )
    }

    func refresh(pinboards: [Pinboard]) {
        let selectedID = visibleEntries.indices.contains(selectedIndex)
            ? visibleEntries[selectedIndex].id
            : nil
        self.pinboards = pinboards
        if let boardID = selectedPinboardID,
           let board = pinboards.first(where: { $0.id == boardID }) {
            allEntries = board.entries
            searchField.placeholderString = "搜索“\(board.name)”"
            refilter(selectingID: selectedID, fallbackIndex: selectedIndex)
        } else if selectedPinboardID != nil {
            selectedPinboardID = nil
            allEntries = historyEntries
            searchField.placeholderString = "搜索剪贴板历史"
            refilter(fallbackIndex: 0)
        }
        rebuildPinboardTabs()
        syncPreviewWithSelection()
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

        countLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

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

        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.image = NSImage(
            systemSymbolName: "star",
            accessibilityDescription: "收藏到收藏板"
        )
        favoriteButton.imagePosition = .imageOnly
        favoriteButton.bezelStyle = .roundRect
        favoriteButton.controlSize = .small
        favoriteButton.target = self
        favoriteButton.action = #selector(showFavoriteMenu(_:))
        favoriteButton.toolTip = "收藏到收藏板"

        statusLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        headerContainer.addSubview(countLabel)
        headerContainer.addSubview(searchField)
        headerContainer.addSubview(filterControl)
        headerContainer.addSubview(favoriteButton)
        headerContainer.addSubview(statusLabel)

        // 收藏板标签与头部合并为一行；历史记录固定在最左，收藏板过多时横向滚动。
        let boardScrollView = NSScrollView()
        boardScrollView.translatesAutoresizingMaskIntoConstraints = false
        boardScrollView.drawsBackground = false
        boardScrollView.hasHorizontalScroller = false
        boardScrollView.hasVerticalScroller = false
        boardScrollView.horizontalScrollElasticity = .automatic
        let boardMinimumWidthConstraint = boardScrollView.widthAnchor.constraint(
            greaterThanOrEqualToConstant: 150
        )
        boardMinimumWidthConstraint.priority = .defaultHigh
        boardMinimumWidthConstraint.isActive = true

        let boardDocumentView = NSView()
        boardDocumentView.translatesAutoresizingMaskIntoConstraints = false
        boardScrollView.documentView = boardDocumentView
        headerContainer.addSubview(boardScrollView)

        boardStackView.translatesAutoresizingMaskIntoConstraints = false
        boardStackView.orientation = .horizontal
        boardStackView.alignment = .centerY
        boardStackView.spacing = 7
        boardDocumentView.addSubview(boardStackView)
        NSLayoutConstraint.activate([
            boardDocumentView.leadingAnchor.constraint(equalTo: boardScrollView.contentView.leadingAnchor),
            boardDocumentView.topAnchor.constraint(equalTo: boardScrollView.contentView.topAnchor),
            boardDocumentView.bottomAnchor.constraint(equalTo: boardScrollView.contentView.bottomAnchor),
            boardDocumentView.widthAnchor.constraint(
                greaterThanOrEqualTo: boardScrollView.contentView.widthAnchor
            ),
            boardStackView.leadingAnchor.constraint(equalTo: boardDocumentView.leadingAnchor),
            boardStackView.trailingAnchor.constraint(
                lessThanOrEqualTo: boardDocumentView.trailingAnchor
            ),
            boardStackView.centerYAnchor.constraint(equalTo: boardDocumentView.centerYAnchor)
        ])

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
        collectionView.registerForDraggedTypes([PinboardDragDescriptor.pasteboardType])
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.onBackgroundClick = { [weak self] in
            self?.focusCollectionView()
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

            countLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            countLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            searchField.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 240),

            boardScrollView.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 14),
            boardScrollView.trailingAnchor.constraint(equalTo: filterControl.leadingAnchor, constant: -14),
            boardScrollView.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            boardScrollView.heightAnchor.constraint(equalToConstant: 28),

            statusLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240),

            favoriteButton.trailingAnchor.constraint(
                equalTo: statusLabel.leadingAnchor, constant: -14
            ),
            favoriteButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            favoriteButton.widthAnchor.constraint(equalToConstant: 34),

            filterControl.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -8),
            filterControl.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

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
        rebuildPinboardTabs()
    }

    // MARK: 收藏板

    private func rebuildPinboardTabs() {
        guard isWindowLoaded else { return }
        for view in boardStackView.arrangedSubviews {
            boardStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let historyButton = makeBoardButton(
            title: "最近",
            color: nil,
            isSelected: selectedPinboardID == nil,
            action: #selector(selectHistoryTab(_:))
        )
        historyButton.toolTip = "最近复制的剪贴板历史"
        boardStackView.addArrangedSubview(historyButton)

        for board in pinboards {
            let button = makeBoardButton(
                title: board.name,
                color: board.color,
                isSelected: selectedPinboardID == board.id,
                action: #selector(selectPinboardTab(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(board.id.uuidString)
            button.toolTip = "打开“\(board.name)”；右键可重命名、改色或删除"
            button.menu = makePinboardContextMenu(for: board)
            button.dropHighlightColor = palette.pinboardColor(board.color)
            button.onAcceptHistoryEntry = { [weak self] entryID in
                DispatchQueue.main.async { [weak self] in
                    self?.addDraggedHistoryEntry(entryID, to: board.id)
                }
            }
            boardStackView.addArrangedSubview(button)
        }

        let addButton = makeBoardButton(
            title: "",
            color: nil,
            isSelected: false,
            action: #selector(createPinboardFromTab(_:))
        )
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建收藏板")
        addButton.imagePosition = .imageOnly
        addButton.toolTip = "新建收藏板"
        boardStackView.addArrangedSubview(addButton)
    }

    private func makeBoardButton(
        title: String,
        color: PinboardColor?,
        isSelected: Bool,
        action: Selector
    ) -> PinboardTabButton {
        let button = PinboardTabButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        if let color {
            let resolvedColor = palette.pinboardColor(color)
            button.image = Self.pinboardColorDot(resolvedColor)
            button.imagePosition = .imageLeading
            button.applyStyle(palette: palette, selected: isSelected, tint: resolvedColor)
        } else {
            button.applyStyle(palette: palette, selected: isSelected, tint: nil)
        }
        return button
    }

    private static func pinboardColorDot(_ color: NSColor, diameter: CGFloat = 9) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: 0.5, y: 0.5,
            width: diameter - 1, height: diameter - 1
        )).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func addDraggedHistoryEntry(_ entryID: UUID, to boardID: UUID) {
        guard let entry = historyEntries.first(where: { $0.id == entryID }),
              let board = pinboards.first(where: { $0.id == boardID }) else { return }
        let alreadyContainsEntry = board.entries.contains { $0.payload == entry.payload }
        onAddToPinboard?(entry, boardID)
        statusLabel.stringValue = alreadyContainsEntry
            ? "这项内容已在“\(board.name)”中"
            : "已收藏到“\(board.name)”"
        statusLabel.textColor = palette.accent
    }

    private func makePinboardContextMenu(for board: Pinboard) -> NSMenu {
        let menu = NSMenu()

        let renameItem = NSMenuItem(
            title: "重命名…",
            action: #selector(renamePinboardFromMenu(_:)),
            keyEquivalent: ""
        )
        renameItem.target = self
        renameItem.representedObject = board.id.uuidString
        menu.addItem(renameItem)

        let colorItem = NSMenuItem(title: "颜色", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for color in PinboardColor.allCases {
            let item = NSMenuItem(
                title: color.displayName,
                action: #selector(changePinboardColorFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = Self.pinboardColorDot(palette.pinboardColor(color))
            item.state = board.color == color ? .on : .off
            item.representedObject = "\(board.id.uuidString)|\(color.rawValue)"
            colorMenu.addItem(item)
        }
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)
        menu.addItem(.separator())

        let deleteItem = NSMenuItem(
            title: "删除收藏板…",
            action: #selector(deletePinboardFromMenu(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.representedObject = board.id.uuidString
        menu.addItem(deleteItem)
        return menu
    }

    @objc private func selectHistoryTab(_ sender: NSButton) {
        switchSource(to: nil)
    }

    @objc private func selectPinboardTab(_ sender: NSButton) {
        guard let rawID = sender.identifier?.rawValue, let id = UUID(uuidString: rawID) else { return }
        switchSource(to: id)
    }

    private func switchSource(to pinboardID: UUID?) {
        // 切换数据源后原预览指向的条目可能已不在列表中，先关闭再重建状态。
        closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: false)
        closeQuickLookIfNeeded(restoreBrowsingFocus: false)
        selectedPinboardID = pinboardID
        if let pinboardID,
           let board = pinboards.first(where: { $0.id == pinboardID }) {
            allEntries = board.entries
            searchField.placeholderString = "搜索“\(board.name)”"
        } else {
            selectedPinboardID = nil
            allEntries = historyEntries
            searchField.placeholderString = "搜索剪贴板历史"
        }
        query = ""
        searchField.stringValue = ""
        typeFilter = .all
        filterControl.selectedSegment = 0
        selectedIndex = 0
        rebuildPinboardTabs()
        refilter(fallbackIndex: 0)
        focusCollectionView()
    }

    @objc private func createPinboardFromTab(_ sender: NSButton) {
        promptToCreatePinboard(adding: nil)
    }

    private func promptToCreatePinboard(adding entry: ClipboardEntry?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "新建收藏板"
        alert.informativeText = "收藏板用于长期保存常用文本、命令、图片或文件。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let nameField = NSTextField(string: "")
        nameField.placeholderString = "名称，例如：常用命令"
        // 颜色直接点选色点，选中项带描边圈，比弹出菜单更直观。
        let colorPicker = PinboardColorPickerView(
            colors: PinboardColor.allCases.map { palette.pinboardColor($0) },
            names: PinboardColor.allCases.map(\.displayName)
        )
        colorPicker.select(index: pinboards.count % PinboardColor.allCases.count)

        let form = NSStackView(views: [nameField, colorPicker])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 10
        form.frame = NSRect(x: 0, y: 0, width: 280, height: 62)
        alert.accessoryView = form
        alert.window.initialFirstResponder = nameField

        alert.beginSheetModal(for: window) { [weak self, weak nameField, weak colorPicker] response in
            guard response == .alertFirstButtonReturn,
                  let self,
                  let name = nameField?.stringValue,
                  let selectedIndex = colorPicker?.selectedIndex,
                  PinboardColor.allCases.indices.contains(selectedIndex) else {
                return
            }
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.statusLabel.stringValue = "收藏板名称不能为空"
                self.statusLabel.textColor = .systemOrange
                NSSound.beep()
                DispatchQueue.main.async { [weak self] in
                    self?.promptToCreatePinboard(adding: entry)
                }
                return
            }
            guard let board = self.onCreatePinboard?(
                name,
                PinboardColor.allCases[selectedIndex]
            ) else { return }
            if let entry {
                self.onAddToPinboard?(entry, board.id)
                self.statusLabel.stringValue = "已收藏到“\(board.name)”"
                self.statusLabel.textColor = self.palette.accent
            } else {
                self.switchSource(to: board.id)
            }
        }
    }

    @objc private func renamePinboardFromMenu(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let id = UUID(uuidString: rawID),
              let board = pinboards.first(where: { $0.id == id }),
              let window else { return }

        let alert = NSAlert()
        alert.messageText = "重命名收藏板"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let nameField = NSTextField(string: board.name)
        nameField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = nameField
        alert.window.initialFirstResponder = nameField
        alert.beginSheetModal(for: window) { [weak self, weak nameField] response in
            guard response == .alertFirstButtonReturn,
                  let name = nameField?.stringValue else { return }
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self?.statusLabel.stringValue = "收藏板名称不能为空"
                self?.statusLabel.textColor = .systemOrange
                NSSound.beep()
                return
            }
            self?.onRenamePinboard?(id, name)
        }
    }

    @objc private func changePinboardColorFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else { return }
        let parts = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let id = UUID(uuidString: parts[0]),
              let color = PinboardColor(rawValue: parts[1]) else { return }
        onSetPinboardColor?(id, color)
    }

    @objc private func deletePinboardFromMenu(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let id = UUID(uuidString: rawID),
              let board = pinboards.first(where: { $0.id == id }),
              let window else { return }
        let alert = NSAlert()
        alert.messageText = "删除收藏板“\(board.name)”？"
        alert.informativeText = "其中的 \(board.entries.count) 项收藏会一并删除，此操作无法撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.onDeletePinboard?(id)
        }
    }

    @objc private func showFavoriteMenu(_ sender: NSButton) {
        guard selectedPinboardID == nil else {
            // 收藏板内的内容已在收藏板中，再次收藏没有意义。
            NSSound.beep()
            return
        }
        guard visibleEntries.indices.contains(selectedIndex) else { return }
        let entry = visibleEntries[selectedIndex]
        guard !pinboards.isEmpty else {
            promptToCreatePinboard(adding: entry)
            return
        }

        let menu = NSMenu()
        // 菜单标题让用户明确这个动作是"收藏到某块板"，而不是凭空出现的列表。
        let header = NSMenuItem(title: "收藏到收藏板", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: "收藏到收藏板",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        menu.addItem(header)
        for board in pinboards {
            let item = NSMenuItem(
                title: board.name,
                action: #selector(addSelectionToPinboard(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = Self.pinboardColorDot(palette.pinboardColor(board.color))
            item.representedObject = board.id.uuidString
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let createItem = NSMenuItem(
            title: "新建收藏板…",
            action: #selector(createPinboardForSelection(_:)),
            keyEquivalent: ""
        )
        createItem.target = self
        menu.addItem(createItem)
        // 优先把菜单放在选中卡片下方，让“收藏”这个动作和它的目标内容在视觉上连在一起；
        // 卡片不可见时（例如键盘触发后列表未布局）才退回按钮位置。
        collectionView.layoutSubtreeIfNeeded()
        if let cardView = collectionView.item(at: selectedIndex)?.view {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: cardView.bounds.height + 4),
                in: cardView
            )
        } else {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height + 3),
                in: sender
            )
        }
    }

    @objc private func addSelectionToPinboard(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let id = UUID(uuidString: rawID),
              let board = pinboards.first(where: { $0.id == id }),
              visibleEntries.indices.contains(selectedIndex) else { return }
        let entry = visibleEntries[selectedIndex]
        let alreadyContainsEntry = board.entries.contains { $0.payload == entry.payload }
        onAddToPinboard?(entry, id)
        statusLabel.stringValue = alreadyContainsEntry
            ? "这项内容已在“\(board.name)”中"
            : "已收藏到“\(board.name)”"
        statusLabel.textColor = palette.accent
    }

    @objc private func createPinboardForSelection(_ sender: NSMenuItem) {
        guard visibleEntries.indices.contains(selectedIndex) else { return }
        promptToCreatePinboard(adding: visibleEntries[selectedIndex])
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
        if let panel = notification.object as? QLPreviewPanel {
            positionQuickLookPanel(panel)
            return
        }
        updateContentInsets()
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? QLPreviewPanel else { return }
        positionQuickLookPanel(panel)
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
        if visibleEntries.isEmpty {
            closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: false)
            closeQuickLookIfNeeded(restoreBrowsingFocus: false)
        } else {
            syncPreviewWithSelection()
        }
    }

    private func updateHeaderState() {
        let isFiltering = !query.isEmpty || typeFilter != .all
        countLabel.stringValue = isFiltering
            ? "匹配 \(visibleEntries.count) / \(allEntries.count)"
            : "\(allEntries.count) 项"

        // 按钮常驻避免布局跳动；收藏板视图下没有可收藏的对象，置灰即可。
        favoriteButton.isEnabled = selectedPinboardID == nil && !visibleEntries.isEmpty

        if allEntries.isEmpty {
            emptyLabel.stringValue = selectedPinboardID == nil
                ? "还没有记录 · 先复制一些文本、图片或文件"
                : "这个收藏板还是空的 · 回到“最近”选择内容并收藏"
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
        let search = shortcutStore.displayString(for: .toggleSearchFocus)
        let preview = shortcutStore.displayString(for: .toggleQuickLook)
        let paste = shortcutStore.displayString(for: .pasteSelection)
        let close = shortcutStore.displayString(for: .clearSearchOrClose)
        let favorite = shortcutStore.displayString(for: .addToPinboard)
        let delete = shortcutStore.displayString(for: .deleteSelection)
        let isFiltering = !query.isEmpty || typeFilter != .all
        if selectedPinboardID != nil, isFiltering, !isSearchFieldFocused {
            hintLabel.stringValue = "当前正在筛选 · 清除搜索并选择“全部”后可拖动调整顺序"
        } else if isSearchFieldFocused {
            let closeHint = query.isEmpty ? "\(close) 关闭" : "\(close) 清除搜索"
            hintLabel.stringValue = "输入筛选 · \(search) 返回浏览 · \(preview) 预览 · \(paste) 粘贴 · \(closeHint)"
        } else if selectedPinboardID != nil {
            hintLabel.stringValue = "单击复制 · \(preview) 预览 · \(search) 搜索 · \(delete) 移出 · \(paste) 粘贴 · \(close) 关闭"
        } else {
            hintLabel.stringValue = "单击复制 · \(preview) 预览 · \(search) 搜索 · \(favorite) 收藏 · \(paste) 粘贴 · \(close) 关闭"
        }
    }

    // MARK: 选择与动作

    private func moveSelection(by offset: Int) {
        guard !visibleEntries.isEmpty else { return }
        focusCollectionView()
        let newIndex = min(max(selectedIndex + offset, 0), visibleEntries.count - 1)
        selectAndChoose(index: newIndex, notifyWhenUnchanged: true)
    }

    private var isSearchFieldFocused: Bool {
        guard let editor = searchField.currentEditor() else { return false }
        return window?.firstResponder === editor
    }

    private var isComposingSearchText: Bool {
        guard isSearchFieldFocused,
              let editor = searchField.currentEditor() as? NSTextView else { return false }
        return editor.hasMarkedText()
    }

    private func focusCollectionView() {
        window?.makeFirstResponder(collectionView)
        updateHintLabel()
    }

    private func focusSearchField() {
        window?.makeFirstResponder(searchField)
        updateHintLabel()
    }
    // MARK: 自适应预览与 Quick Look

    private var isAdaptivePreviewVisible: Bool {
        adaptivePreviewController.isVisible
    }

    private var isQuickLookVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()?.isVisible == true
    }

    private func togglePreview() {
        if isAdaptivePreviewVisible {
            closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: true)
            return
        }
        if isQuickLookVisible {
            closeQuickLookIfNeeded(restoreBrowsingFocus: true)
            return
        }

        if showAdaptivePreviewIfSupported() {
            return
        }
        showQuickLook()
    }

    private func showAdaptivePreviewIfSupported() -> Bool {
        guard visibleEntries.indices.contains(selectedIndex) else { return false }
        guard AdaptivePreviewController.supports(entry: visibleEntries[selectedIndex]) else {
            return false
        }
        collectionView.layoutSubtreeIfNeeded()
        guard let itemView = collectionView.item(at: selectedIndex)?.view else { return false }

        // 快速连续切换时也只允许一种预览存在。
        if isQuickLookVisible {
            closeQuickLookIfNeeded(restoreBrowsingFocus: false)
        }

        return adaptivePreviewController.show(
            entry: visibleEntries[selectedIndex],
            relativeTo: itemView,
            palette: palette
        ) { [weak self] in
            guard let self else { return }
            self.closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: false)
            self.showQuickLook()
        }
    }

    /// 选择变化后让预览跟随当前条目：文本/图片保持轻量气泡，文件保持大屏 Quick Look。
    /// 两种模式之间双向切换，锚点未就绪时有限重试，绝不把文本/图片错误地留在大屏里。
    private func syncPreviewWithSelection(retriesRemaining: Int = 3) {
        guard isAdaptivePreviewVisible || isQuickLookVisible else { return }
        // scrollToItems 的布局在当前事件尾部才稳定；等布局完成后再换锚点。
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.window?.isVisible == true,
                  self.visibleEntries.indices.contains(self.selectedIndex) else { return }
            let entry = self.visibleEntries[self.selectedIndex]

            if AdaptivePreviewController.supports(entry: entry) {
                // showAdaptivePreviewIfSupported 内部会先关掉 Quick Look。
                if !self.showAdaptivePreviewIfSupported(), retriesRemaining > 0 {
                    // 快速切换时新卡片可能尚未滚动到位、锚点视图还没生成，稍后重试。
                    self.syncPreviewWithSelection(retriesRemaining: retriesRemaining - 1)
                }
                return
            }

            // 文件走完整 Quick Look。
            self.closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: false)
            if self.isQuickLookVisible {
                guard self.prepareQuickLookPreview(),
                      let panel = QLPreviewPanel.shared() else {
                    self.closeQuickLookIfNeeded(restoreBrowsingFocus: false)
                    return
                }
                panel.reloadData()
                self.positionQuickLookPanel(panel)
            } else {
                self.showQuickLook()
            }
        }
    }

    private func closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: Bool) {
        if isAdaptivePreviewVisible {
            adaptivePreviewController.close()
        }
        if restoreBrowsingFocus {
            window?.makeKeyAndOrderFront(nil)
            focusCollectionView()
        }
    }

    private func showQuickLook() {
        closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: false)
        guard prepareQuickLookPreview(), let panel = QLPreviewPanel.shared() else {
            NSSound.beep()
            return
        }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        positionQuickLookPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        // Quick Look 内容异步载入后可能重算窗口尺寸，再约束一次目标屏幕。
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible else { return }
            self.positionQuickLookPanel(panel)
        }
    }

    private func positionQuickLookPanel(_ panel: QLPreviewPanel) {
        guard !isPositioningQuickLookPanel else { return }
        collectionView.layoutSubtreeIfNeeded()
        let selectedItemScreen = collectionView.item(at: selectedIndex)?.view.window?.screen
        guard let screen = selectedItemScreen ?? window?.screen else { return }

        let visibleFrame = screen.visibleFrame
        let targetFrame = AdaptivePreviewSizing.centeredQuickLookFrame(
            panelSize: panel.frame.size,
            visibleFrame: visibleFrame
        )
        guard !panel.frame.approximatelyEquals(targetFrame) else { return }
        isPositioningQuickLookPanel = true
        panel.setFrame(targetFrame, display: false)
        isPositioningQuickLookPanel = false
    }

    private func closeQuickLookIfNeeded(restoreBrowsingFocus: Bool) {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() {
            if panel.isVisible { panel.orderOut(nil) }
            panel.dataSource = nil
            panel.delegate = nil
        }
        quickLookPreviewURL = nil
        cleanupQuickLookTempFiles()

        if restoreBrowsingFocus {
            window?.makeKeyAndOrderFront(nil)
            focusCollectionView()
        }
    }

    private func prepareQuickLookPreview() -> Bool {
        guard visibleEntries.indices.contains(selectedIndex) else {
            quickLookPreviewURL = nil
            return false
        }

        cleanupQuickLookTempFiles()
        let entry = visibleEntries[selectedIndex]
        switch entry.payload {
        case .files(let paths):
            guard let path = paths.first, FileManager.default.fileExists(atPath: path) else {
                quickLookPreviewURL = nil
                return false
            }
            quickLookPreviewURL = URL(fileURLWithPath: path)
        case .image(let data, let pasteboardType):
            let ext = pasteboardType == NSPasteboard.PasteboardType.tiff.rawValue ? "tiff" : "png"
            quickLookPreviewURL = writeQuickLookTemp(
                data: data,
                filename: "\(entry.id.uuidString).\(ext)"
            )
        case .text(let text):
            quickLookPreviewURL = writeQuickLookTemp(
                data: Data(text.utf8),
                filename: "\(entry.id.uuidString).txt"
            )
        }
        return quickLookPreviewURL != nil
    }

    private func writeQuickLookTemp(data: Data, filename: String) -> URL? {
        let directory = quickLookTempDirectory
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private var quickLookTempDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cpsmart-quicklook", isDirectory: true)
    }

    private func cleanupQuickLookTempFiles() {
        try? FileManager.default.removeItem(at: quickLookTempDirectory)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookPreviewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        quickLookPreviewURL as? QLPreviewItem
    }
    func previewPanel(
        _ panel: QLPreviewPanel!,
        sourceFrameOnScreenFor item: QLPreviewItem!
    ) -> NSRect {
        guard let window, let itemView = collectionView.item(at: selectedIndex)?.view else {
            return .zero
        }
        return window.convertToScreen(itemView.convert(itemView.bounds, to: nil))
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        quickLookPreviewURL = nil
        cleanupQuickLookTempFiles()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.isVisible == true, !self.isDismissing else { return }
            self.window?.makeKeyAndOrderFront(nil)
            self.focusCollectionView()
        }
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
        syncPreviewWithSelection()
    }

    private func chooseEntry(at index: Int) {
        guard visibleEntries.indices.contains(index) else { return }
        let entry = visibleEntries[index]
        onChoose?(entry)
        statusLabel.stringValue = "已选择并复制 \(index + 1) / \(visibleEntries.count) · 双击可粘贴"
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
            statusLabel.stringValue = "请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 cpsmart"
            statusLabel.textColor = .systemOrange
            NSSound.beep()
            showAccessibilityPermissionHelp()
        case .targetUnavailable:
            statusLabel.stringValue = "无法找到刚才使用的应用，请关闭浮窗后重试"
            statusLabel.textColor = .systemOrange
            NSSound.beep()
        }
    }

    private func showAccessibilityPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "需要开启“辅助功能”权限"
        alert.informativeText = """
        请按下面的路径操作：

        系统设置 → 隐私与安全性 → 辅助功能

        1. 确认 cpsmart 已放在“应用程序”文件夹。
        2. 点击应用列表下方的“+”，选择“应用程序”里的 cpsmart。
        3. 打开 cpsmart 右侧的开关；按系统提示输入密码或使用 Touch ID。
        4. 完全退出 cpsmart，然后重新打开。

        如果列表中已有 cpsmart 但仍然无法粘贴，请先用“−”删除旧项，再用“+”重新添加。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开辅助功能设置")
        alert.addButton(withTitle: "稍后")

        guard alert.runModal() == .alertFirstButtonReturn,
              let settingsURL = URL(
                  string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
              ) else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    private func deleteSelection() {
        guard visibleEntries.indices.contains(selectedIndex) else { return }
        let entry = visibleEntries[selectedIndex]
        if let selectedPinboardID {
            onRemoveFromPinboard?(entry, selectedPinboardID)
        } else {
            onDelete?(entry)
        }
    }

    private func togglePinSelection() {
        // 收藏板内顺序由拖动排序管理，置顶没有语义；给出可感知反馈而不是静默吞键。
        guard selectedPinboardID == nil else {
            NSSound.beep()
            return
        }
        guard visibleEntries.indices.contains(selectedIndex) else { return }
        onTogglePin?(visibleEntries[selectedIndex])
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
        focusSearchField()
    }

    /// 开发用：直接选中演示记录并打开预览，便于自动截图检查不同内容尺寸。
    func showDemoPreview(at index: Int) {
        guard visibleEntries.indices.contains(index) else { return }
        selectAndChoose(index: index, notifyWhenUnchanged: true)
        togglePreview()
    }

    func applyDemoPinboard(at index: Int) {
        guard pinboards.indices.contains(index) else { return }
        switchSource(to: pinboards[index].id)
    }

    /// 开发用：直接渲染浮窗内容，避免多屏坐标和窗口共享策略影响自动截图。
    @discardableResult
    func writeDemoSnapshot(to url: URL) -> Bool {
        guard let contentView = window?.contentView else { return false }
        contentView.layoutSubtreeIfNeeded()
        guard let representation = contentView.bitmapImageRepForCachingDisplay(
            in: contentView.bounds
        ) else { return false }
        contentView.cacheDisplay(in: contentView.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("cpsmart could not write demo snapshot: %@", error.localizedDescription)
            return false
        }
    }
    #endif

    func controlTextDidChange(_ notification: Notification) {
        query = searchField.stringValue
        refilter(fallbackIndex: 0)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        updateHintLabel()
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        typeFilter = TypeFilter(rawValue: sender.selectedSegment) ?? .all
        refilter(fallbackIndex: 0)
        focusCollectionView()
    }

    // MARK: 关闭

    private func dismiss(restorePreviousApplication: Bool) {
        guard let window, window.isVisible, !isDismissing else { return }
        isDismissing = true
        dismissalGeneration += 1
        let generation = dismissalGeneration
        removeKeyboardMonitor()
        closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: false)
        closeQuickLookIfNeeded(restoreBrowsingFocus: false)
        thumbnailProvider.cancelAll()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Theme.exitDuration
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak window] in
            guard let self else { return }
            // 动画期间若被重新唤起，此回调已作废，不能隐藏新窗口。
            guard generation == self.dismissalGeneration else { return }
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
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self,
                  let window = self.window,
                  window.isVisible,
                  event.window === window else {
                return event
            }

            let pointInSearchField = self.searchField.convert(event.locationInWindow, from: nil)
            guard !self.searchField.bounds.contains(pointInSearchField) else { return event }

            // 让控件先完成自己的点击行为，再把键盘焦点交给卡片列表。
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, window.isVisible, !self.isDismissing else { return }
                self.focusCollectionView()
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    private func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        // 浮窗上挂着 sheet（新建/重命名收藏板等）时，键盘属于 sheet 的输入框，
        // 不能按历史窗口的快捷键逻辑拦截，否则名称根本无法输入。
        if window?.attachedSheet != nil { return false }

        if isAdaptivePreviewVisible {
            // 与 Quick Look 使用同一组上下文，确保自定义快捷键在轻量预览中同样生效。
            switch shortcutMatcher.action(for: event, context: .quickLook) {
            case .toggleQuickLook, .clearSearchOrClose:
                if !event.isARepeat {
                    closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: true)
                }
                return true
            case .selectPrevious:
                moveSelection(by: -1)
                return true
            case .selectNext:
                moveSelection(by: 1)
                return true
            default:
                // 允许 ⌘C 等文本选择相关快捷键继续交给只读预览文本。
                return false
            }
        }

        if isQuickLookVisible {
            switch shortcutMatcher.action(for: event, context: .quickLook) {
            case .toggleQuickLook, .clearSearchOrClose:
                if !event.isARepeat {
                    closeQuickLookIfNeeded(restoreBrowsingFocus: true)
                }
            case .selectPrevious:
                moveSelection(by: -1)
                syncPreviewWithSelection()
            case .selectNext:
                moveSelection(by: 1)
                syncPreviewWithSelection()
            default:
                break
            }
            return true
        }

        let context: ShortcutContext
        if isComposingSearchText {
            context = .composingSearchText
        } else if isSearchFieldFocused {
            context = .searching
        } else {
            context = .browsing
        }

        guard let action = shortcutMatcher.action(for: event, context: context) else {
            if context == .browsing, isPrintableTextInput(event) {
                // 浏览态必须先使用配置的搜索快捷键，避免无意按键改变筛选结果。
                return true
            }
            return false
        }

        switch action {
        case .selectPrevious:
            moveSelection(by: -1)
        case .selectNext:
            moveSelection(by: 1)
        case .toggleSearchFocus:
            if isSearchFieldFocused {
                focusCollectionView()
            } else {
                focusSearchField()
            }
        case .pasteSelection:
            confirmAndPaste()
        case .toggleQuickLook:
            if !event.isARepeat {
                togglePreview()
            }
        case .togglePin:
            togglePinSelection()
        case .addToPinboard:
            showFavoriteMenu(favoriteButton)
        case .deleteSelection:
            deleteSelection()
        case .filterAll:
            applyFilterShortcut(segment: 0)
        case .filterText:
            applyFilterShortcut(segment: 1)
        case .filterImage:
            applyFilterShortcut(segment: 2)
        case .filterFiles:
            applyFilterShortcut(segment: 3)
        case .clearSearchOrClose:
            if !query.isEmpty {
                clearSearch()
            } else {
                dismiss(restorePreviousApplication: true)
            }
        case .toggleHistory:
            return false
        }
        return true
    }

    private func applyFilterShortcut(segment: Int) {
        filterControl.selectedSegment = segment
        filterChanged(filterControl)
    }

    private func isPrintableTextInput(_ event: NSEvent) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .function]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty,
              let characters = event.characters,
              !characters.isEmpty else { return false }
        return characters.unicodeScalars.contains {
            !CharacterSet.controlCharacters.contains($0)
        }
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
        let representedEntry = visibleEntries[indexPath.item]
        item.configure(
            with: representedEntry,
            thumbnails: thumbnailProvider,
            palette: palette
        )
        item.onClick = { [weak self] clickCount in
            guard let self else { return }
            self.focusCollectionView()
            self.selectAndChoose(index: indexPath.item, notifyWhenUnchanged: true)
            if clickCount >= 2 {
                self.confirmAndPaste()
            }
        }
        item.onDrag = { [weak self] event, sourceView in
            self?.beginCardDrag(entry: representedEntry, event: event, sourceView: sourceView)
        }
        return item
    }

    private func beginCardDrag(entry: ClipboardEntry, event: NSEvent, sourceView: NSView) {
        if selectedPinboardID != nil, (!query.isEmpty || typeFilter != .all) {
            NSSound.beep()
            statusLabel.stringValue = "清除搜索并选择“全部”后可调整收藏顺序"
            statusLabel.textColor = .systemOrange
            return
        }

        let descriptor = PinboardDragDescriptor(
            entryID: entry.id,
            sourcePinboardID: selectedPinboardID
        )
        let draggingItem = NSDraggingItem(pasteboardWriter: descriptor.pasteboardItem())
        let frame = sourceView.convert(sourceView.bounds, to: collectionView)
        draggingItem.setDraggingFrame(frame, contents: snapshotImage(of: sourceView))
        let session = collectionView.beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func snapshotImage(of view: NSView) -> NSImage {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return NSImage(size: view.bounds.size)
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(representation)
        return image
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        selectedPinboardID == nil ? .copy : .move
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        canDragItemsAt indexPaths: Set<IndexPath>,
        with event: NSEvent
    ) -> Bool {
        guard indexPaths.count == 1,
              let indexPath = indexPaths.first,
              visibleEntries.indices.contains(indexPath.item) else { return false }
        if selectedPinboardID != nil {
            return query.isEmpty && typeFilter == .all
        }
        return true
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard visibleEntries.indices.contains(indexPath.item) else { return nil }
        return PinboardDragDescriptor(
            entryID: visibleEntries[indexPath.item].id,
            sourcePinboardID: selectedPinboardID
        ).pasteboardItem()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        guard query.isEmpty,
              typeFilter == .all,
              let boardID = selectedPinboardID,
              let descriptor = PinboardDragDescriptor.read(from: draggingInfo.draggingPasteboard),
              descriptor.sourcePinboardID == boardID else { return [] }
        proposedDropOperation.pointee = .before
        return .move
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard query.isEmpty,
              typeFilter == .all,
              let boardID = selectedPinboardID,
              let descriptor = PinboardDragDescriptor.read(from: draggingInfo.draggingPasteboard),
              descriptor.sourcePinboardID == boardID else { return false }
        onMovePinboardEntry?(descriptor.entryID, boardID, indexPath.item)
        return true
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard !suppressSelectionCallback, let indexPath = indexPaths.first else { return }
        selectedIndex = indexPath.item
        chooseEntry(at: indexPath.item)
        syncPreviewWithSelection()
    }
}
