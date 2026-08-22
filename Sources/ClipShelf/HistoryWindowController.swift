import AppKit

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

    private let cardView = ClickableCardView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    override func loadView() {
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 12
        cardView.layer?.borderWidth = 1
        cardView.layer?.masksToBounds = true
        cardView.setAccessibilityRole(.button)
        view = cardView

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .secondaryLabelColor
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 3

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        cardView.addSubview(iconView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            iconView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            detailLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            detailLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            detailLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -10)
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
            cardView.layer?.borderWidth = 2
            cardView.layer?.borderColor = NSColor.controlAccentColor.cgColor
            cardView.layer?.backgroundColor = NSColor.controlAccentColor
                .withAlphaComponent(0.16)
                .cgColor
        } else {
            cardView.layer?.borderWidth = 1
            cardView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
            cardView.layer?.backgroundColor = NSColor.controlBackgroundColor
                .withAlphaComponent(0.58)
                .cgColor
        }
    }

    private static func preview(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(3)
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

final class HistoryWindowController: NSWindowController,
    NSCollectionViewDataSource,
    NSCollectionViewDelegate
{
    var onChoose: ((ClipboardEntry) -> Void)?
    var onDelete: ((ClipboardEntry) -> Void)?

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("HistoryCollectionItem")
    private let collectionView = KeyboardCollectionView()
    private let countLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "选择后立即写入系统剪贴板")
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
        panel.title = "ClipShelf 剪贴板历史"
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

        let effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 18
        effectView.layer?.masksToBounds = true
        contentView.addSubview(effectView)

        let titleLabel = NSTextField(labelWithString: "剪贴板历史")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        selectionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        selectionLabel.textColor = .secondaryLabelColor
        selectionLabel.alignment = .right
        selectionLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 180, height: 112)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
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
        collectionView.onConfirm = { [weak self] in
            self?.dismiss(restorePreviousApplication: true)
        }
        collectionView.onDelete = { [weak self] in self?.deleteSelection() }
        collectionView.onEscape = { [weak self] in
            self?.dismiss(restorePreviousApplication: true)
        }
        scrollView.documentView = collectionView

        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let helpLabel = NSTextField(labelWithString: "← → 切换并复制   ·   点击选择   ·   ↩ 完成   ·   ⌫ 删除   ·   Esc 关闭")
        helpLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        helpLabel.textColor = .tertiaryLabelColor
        helpLabel.alignment = .center
        helpLabel.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(titleLabel)
        effectView.addSubview(countLabel)
        effectView.addSubview(selectionLabel)
        effectView.addSubview(scrollView)
        effectView.addSubview(emptyLabel)
        effectView.addSubview(helpLabel)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 18),
            titleLabel.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 14),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),

            selectionLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -18),
            selectionLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            selectionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -14),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.heightAnchor.constraint(equalToConstant: 124),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            helpLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 18),
            helpLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -18),
            helpLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            helpLabel.bottomAnchor.constraint(lessThanOrEqualTo: effectView.bottomAnchor, constant: -10)
        ])
    }

    private func positionWindow(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let width = min(900, max(500, visibleFrame.width - 48))
        let height: CGFloat = 210
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.minY + 24
        )
        window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }

    private func reloadCollection(selecting index: Int?, notify: Bool) {
        suppressSelectionCallback = true
        collectionView.reloadData()
        emptyLabel.isHidden = !entries.isEmpty
        countLabel.stringValue = "\(entries.count) 条"

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
            selectionLabel.stringValue = "选择后立即写入系统剪贴板"
            selectionLabel.textColor = .secondaryLabelColor
        }
    }

    private func moveSelection(by offset: Int) {
        guard !entries.isEmpty else { return }
        let newIndex = min(max(selectedIndex + offset, 0), entries.count - 1)
        selectAndChoose(index: newIndex)
    }

    private func selectAndChoose(index: Int) {
        guard entries.indices.contains(index) else { return }
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
        selectionLabel.stringValue = "✓ 已切换到第 \(index + 1) 条"
        selectionLabel.textColor = .controlAccentColor
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
            self?.selectAndChoose(index: indexPath.item)
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
