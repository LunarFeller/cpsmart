import AppKit

private final class FloatingHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class InvisibleScroller: NSScroller {
    override func draw(_ dirtyRect: NSRect) {}
    override func drawKnob() {}
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
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
            onDelete?()
        case 53:
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class ClickableCardView: NSView {
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
        onHover?()
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

private final class HistoryCollectionItem: NSCollectionViewItem {
    var onClick: (() -> Void)? {
        didSet { cardView.onClick = onClick }
    }
    var onHover: (() -> Void)? {
        didSet { cardView.onHover = onHover }
    }

    private let cardView = ClickableCardView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    override func loadView() {
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 10
        cardView.layer?.borderWidth = 1
        cardView.layer?.masksToBounds = true
        cardView.setAccessibilityRole(.button)
        view = cardView

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = Self.secondaryTextColor
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 5
        iconView.layer?.masksToBounds = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Self.primaryTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 5

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 10, weight: .medium)
        detailLabel.textColor = Self.secondaryTextColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        cardView.addSubview(iconView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            iconView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 13),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            detailLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            detailLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            detailLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12)
        ])

        updateSelectionAppearance()
    }

    func configure(with entry: ClipboardEntry) {
        switch entry.payload {
        case .text(let text):
            iconView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "文本")
            titleLabel.stringValue = Self.preview(text)
            detailLabel.stringValue = "文本 · \(Self.relativeDate.string(for: entry.createdAt) ?? "刚刚")"

        case .image(let data, _):
            iconView.image = NSImage(data: data)
                ?? NSImage(systemSymbolName: "photo", accessibilityDescription: "图片")
            if let image = NSImage(data: data) {
                titleLabel.stringValue = "图片\n\(Int(image.size.width)) × \(Int(image.size.height))"
            } else {
                titleLabel.stringValue = "图片"
            }
            detailLabel.stringValue = "图片 · \(Self.byteCount.string(fromByteCount: Int64(data.count)))"

        case .files(let paths):
            iconView.image = NSWorkspace.shared.icon(forFile: paths.first ?? "")
            if paths.count == 1 {
                titleLabel.stringValue = URL(fileURLWithPath: paths[0]).lastPathComponent
            } else {
                titleLabel.stringValue = "\(paths.count) 个文件"
            }
            detailLabel.stringValue = "文件 · \(Self.relativeDate.string(for: entry.createdAt) ?? "刚刚")"
        }

        cardView.setAccessibilityLabel(titleLabel.stringValue)
    }

    private func updateSelectionAppearance() {
        guard isViewLoaded else { return }
        if isSelected {
            cardView.layer?.borderWidth = 1.5
            cardView.layer?.borderColor = Self.accentColor.cgColor
            cardView.layer?.backgroundColor = Self.selectedBackgroundColor.cgColor
        } else {
            cardView.layer?.borderWidth = 1
            cardView.layer?.borderColor = Self.cardBorderColor.cgColor
            cardView.layer?.backgroundColor = Self.cardBackgroundColor.cgColor
        }
    }

    private static func preview(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(5)
            .joined(separator: "\n")
    }

    private static let primaryTextColor = NSColor(
        srgbRed: 0.93,
        green: 0.95,
        blue: 0.98,
        alpha: 1
    )
    private static let secondaryTextColor = NSColor(
        srgbRed: 0.55,
        green: 0.60,
        blue: 0.68,
        alpha: 1
    )
    private static let cardBackgroundColor = NSColor(
        srgbRed: 0.09,
        green: 0.10,
        blue: 0.12,
        alpha: 0.96
    )
    private static let cardBorderColor = NSColor.white.withAlphaComponent(0.11)
    private static let selectedBackgroundColor = NSColor(
        srgbRed: 0.08,
        green: 0.15,
        blue: 0.24,
        alpha: 1
    )
    private static let accentColor = NSColor(
        srgbRed: 0.18,
        green: 0.52,
        blue: 0.96,
        alpha: 1
    )

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

final class HistoryWindowController: NSWindowController,
    NSCollectionViewDataSource,
    NSCollectionViewDelegate
{
    var onChoose: ((ClipboardEntry) -> Void)?
    var onPaste: ((NSRunningApplication?) -> Bool)?
    var onDelete: ((ClipboardEntry) -> Void)?

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("HistoryCollectionItem")
    private let collectionView = KeyboardCollectionView()
    private let countLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "还没有记录 · 先复制一些文本、图片或文件")
    private var entries: [ClipboardEntry] = []
    private var selectedIndex = 0
    private var previousApplication: NSRunningApplication?
    private var suppressSelectionCallback = false

    init() {
        let panel = FloatingHistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 210),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "cpsmart 剪贴板历史"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        super.init(window: panel)
        buildInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(entries: [ClipboardEntry]) {
        if window?.isVisible == true {
            dismiss(restorePreviousApplication: true)
            return
        }

        previousApplication = NSWorkspace.shared.frontmostApplication
        self.entries = entries
        selectedIndex = 0
        reloadCollection(selecting: entries.isEmpty ? nil : 0, notify: false)

        guard let window else { return }
        positionWindow(window)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(self.collectionView)
        }
    }

    func refresh(entries: [ClipboardEntry]) {
        let selectedID = self.entries.indices.contains(selectedIndex)
            ? self.entries[selectedIndex].id
            : nil
        self.entries = entries

        let newIndex: Int?
        if let selectedID, let matchingIndex = entries.firstIndex(where: { $0.id == selectedID }) {
            newIndex = matchingIndex
        } else if entries.isEmpty {
            newIndex = nil
        } else {
            newIndex = min(selectedIndex, entries.count - 1)
        }
        reloadCollection(selecting: newIndex, notify: false)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let effectView = NSView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor(
            srgbRed: 0.035,
            green: 0.040,
            blue: 0.050,
            alpha: 1
        ).cgColor
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true
        contentView.addSubview(effectView)

        let titleLabel = NSTextField(labelWithString: "cpsmart")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.94)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 10, weight: .medium)
        countLabel.textColor = NSColor.white.withAlphaComponent(0.42)
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        selectionLabel.font = .systemFont(ofSize: 10, weight: .medium)
        selectionLabel.textColor = NSColor.white.withAlphaComponent(0.48)
        selectionLabel.alignment = .right
        selectionLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.horizontalScroller = InvisibleScroller()
        scrollView.drawsBackground = false

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 214, height: 150)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        collectionView.collectionViewLayout = layout
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
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = NSColor.white.withAlphaComponent(0.42)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(titleLabel)
        effectView.addSubview(countLabel)
        effectView.addSubview(selectionLabel)
        effectView.addSubview(scrollView)
        effectView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 12),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),

            selectionLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
            selectionLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            selectionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    private func positionWindow(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let width = visibleFrame.width
        let height: CGFloat = 210
        let origin = NSPoint(
            x: visibleFrame.minX,
            y: visibleFrame.minY
        )
        window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }

    private func reloadCollection(selecting index: Int?, notify: Bool) {
        suppressSelectionCallback = true
        collectionView.reloadData()
        emptyLabel.isHidden = !entries.isEmpty
        countLabel.stringValue = "\(entries.count) 项"

        if let index, entries.indices.contains(index) {
            selectedIndex = index
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.selectionIndexPaths = [indexPath]
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredHorizontally)
        } else {
            selectedIndex = 0
            collectionView.selectionIndexPaths = []
        }
        suppressSelectionCallback = false
        if notify, let index, entries.indices.contains(index) {
            chooseEntry(at: index)
        } else {
            selectionLabel.stringValue = ""
            selectionLabel.textColor = NSColor.white.withAlphaComponent(0.48)
        }
    }

    private func moveSelection(by offset: Int) {
        guard !entries.isEmpty else { return }
        let newIndex = min(max(selectedIndex + offset, 0), entries.count - 1)
        selectAndChoose(index: newIndex, notifyWhenUnchanged: true)
    }

    private func selectAndChoose(index: Int, notifyWhenUnchanged: Bool) {
        guard entries.indices.contains(index) else { return }
        let selectionChanged = selectedIndex != index
        guard selectionChanged || notifyWhenUnchanged else { return }
        selectedIndex = index
        suppressSelectionCallback = true
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.selectionIndexPaths = [indexPath]
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredHorizontally)
        suppressSelectionCallback = false
        chooseEntry(at: index)
        window?.makeFirstResponder(collectionView)
    }

    private func chooseEntry(at index: Int) {
        guard entries.indices.contains(index) else { return }
        let entry = entries[index]
        onChoose?(entry)
        selectionLabel.stringValue = "已选择 \(index + 1) / \(entries.count)"
        selectionLabel.textColor = NSColor(
            srgbRed: 0.35,
            green: 0.65,
            blue: 1,
            alpha: 1
        )
    }

    private func confirmAndPaste() {
        guard entries.indices.contains(selectedIndex) else { return }
        onChoose?(entries[selectedIndex])
        let pasteStarted = onPaste?(previousApplication) ?? false
        if pasteStarted {
            window?.orderOut(nil)
            previousApplication = nil
        } else {
            selectionLabel.stringValue = "请先允许“辅助功能”权限，然后再次按回车"
            selectionLabel.textColor = .systemOrange
            NSSound.beep()
        }
    }

    private func deleteSelection() {
        guard entries.indices.contains(selectedIndex) else { return }
        onDelete?(entries[selectedIndex])
    }

    private func dismiss(restorePreviousApplication: Bool) {
        window?.orderOut(nil)
        if restorePreviousApplication,
           let previousApplication,
           previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApplication.activate(options: [.activateIgnoringOtherApps])
        }
        previousApplication = nil
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        entries.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: Self.itemIdentifier,
            for: indexPath
        ) as! HistoryCollectionItem
        item.configure(with: entries[indexPath.item])
        item.onClick = { [weak self] in
            self?.selectAndChoose(index: indexPath.item, notifyWhenUnchanged: true)
        }
        item.onHover = { [weak self] in
            self?.selectAndChoose(index: indexPath.item, notifyWhenUnchanged: false)
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
