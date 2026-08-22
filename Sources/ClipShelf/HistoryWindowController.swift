import AppKit

private final class HistoryTableView: NSTableView {
    var onConfirm: (() -> Void)?
    var onDelete: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
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

private final class HistoryCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .secondaryLabelColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with entry: ClipboardEntry) {
        switch entry.payload {
        case .text(let text):
            iconView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "文本")
            titleLabel.stringValue = Self.oneLine(text)
            detailLabel.stringValue = "文本 · \(Self.relativeDate.string(for: entry.createdAt) ?? "刚刚")"

        case .image(let data, _):
            iconView.image = NSImage(data: data)
                ?? NSImage(systemSymbolName: "photo", accessibilityDescription: "图片")
            if let image = NSImage(data: data) {
                titleLabel.stringValue = "图片 · \(Int(image.size.width)) × \(Int(image.size.height))"
            } else {
                titleLabel.stringValue = "图片"
            }
            detailLabel.stringValue = "图片 · \(Self.byteCount.string(fromByteCount: Int64(data.count))) · \(Self.relativeDate.string(for: entry.createdAt) ?? "刚刚")"

        case .files(let paths):
            iconView.image = NSWorkspace.shared.icon(forFile: paths.first ?? "")
            if paths.count == 1 {
                titleLabel.stringValue = URL(fileURLWithPath: paths[0]).lastPathComponent
            } else {
                titleLabel.stringValue = "\(paths.count) 个文件"
            }
            detailLabel.stringValue = "文件 · \(Self.relativeDate.string(for: entry.createdAt) ?? "刚刚")"
        }
    }

    private static func oneLine(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ↵  ")
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
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSSearchFieldDelegate
{
    var onChoose: ((ClipboardEntry) -> Void)?
    var onDelete: ((ClipboardEntry) -> Void)?

    private let tableView = HistoryTableView()
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "还没有剪贴板记录\n复制一些文本、图片或文件后，它们会出现在这里。")
    private var allEntries: [ClipboardEntry] = []
    private var visibleEntries: [ClipboardEntry] = []

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "ClipShelf 剪贴板历史"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.minSize = NSSize(width: 480, height: 360)

        super.init(window: panel)
        buildInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(entries: [ClipboardEntry]) {
        allEntries = entries
        searchField.stringValue = ""
        applyFilter()

        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)

        if visibleEntries.isEmpty {
            window.makeFirstResponder(searchField)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            window.makeFirstResponder(searchField)
        }
    }

    func refresh(entries: [ClipboardEntry]) {
        allEntries = entries
        applyFilter()
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .sidebar
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        contentView.addSubview(effectView)

        let titleLabel = NSTextField(labelWithString: "剪贴板历史")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "搜索历史记录"
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("HistoryColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 56
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(confirmSelection)
        tableView.onConfirm = { [weak self] in self?.confirmSelection() }
        tableView.onDelete = { [weak self] in self?.deleteSelection() }
        tableView.onEscape = { [weak self] in self?.close() }
        scrollView.documentView = tableView

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let privacyLabel = NSTextField(labelWithString: "密码管理器标记的敏感内容不会被记录")
        privacyLabel.font = .systemFont(ofSize: 11)
        privacyLabel.textColor = .tertiaryLabelColor
        privacyLabel.translatesAutoresizingMaskIntoConstraints = false

        let shortcutLabel = NSTextField(labelWithString: "↑↓ 选择   ↩ 复制   ⌫ 删除   Esc 关闭")
        shortcutLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(titleLabel)
        effectView.addSubview(countLabel)
        effectView.addSubview(searchField)
        effectView.addSubview(scrollView)
        effectView.addSubview(emptyLabel)
        effectView.addSubview(privacyLabel)
        effectView.addSubview(shortcutLabel)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 24),
            titleLabel.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 28),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            countLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),

            searchField.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 24),
            searchField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -24),
            searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),

            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: privacyLabel.topAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            privacyLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 24),
            privacyLabel.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -16),

            shortcutLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -24),
            shortcutLabel.centerYAnchor.constraint(equalTo: privacyLabel.centerYAnchor),
            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: privacyLabel.trailingAnchor, constant: 12)
        ])
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            visibleEntries = allEntries
        } else {
            visibleEntries = allEntries.filter {
                $0.payload.searchableText.localizedCaseInsensitiveContains(query)
            }
        }
        tableView.reloadData()
        emptyLabel.isHidden = !visibleEntries.isEmpty
        countLabel.stringValue = "\(visibleEntries.count) 条"

        if !visibleEntries.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func confirmSelection() {
        guard !visibleEntries.isEmpty else { return }
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard visibleEntries.indices.contains(row) else { return }
        onChoose?(visibleEntries[row])
        close()
    }

    private func deleteSelection() {
        let row = tableView.selectedRow
        guard visibleEntries.indices.contains(row) else { return }
        let entry = visibleEntries[row]
        onDelete?(entry)
        let nextRow = min(row, max(visibleEntries.count - 1, 0))
        if !visibleEntries.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleEntries.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? HistoryCellView
            ?? HistoryCellView()
        cell.identifier = identifier
        cell.configure(with: visibleEntries[row])
        return cell
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            let next = min(max(tableView.selectedRow + 1, 0), visibleEntries.count - 1)
            guard next >= 0 else { return true }
            tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            tableView.scrollRowToVisible(next)
            return true
        case #selector(NSResponder.moveUp(_:)):
            let previous = max(tableView.selectedRow - 1, 0)
            guard !visibleEntries.isEmpty else { return true }
            tableView.selectRowIndexes(IndexSet(integer: previous), byExtendingSelection: false)
            tableView.scrollRowToVisible(previous)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            confirmSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }
}
