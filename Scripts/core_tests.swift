import AppKit
import Carbon
import Foundation

@main
struct CoreTests {
    private static let testDefaultsSuiteName = "cpsmartCoreTests-\(UUID().uuidString)"
    private static let testDefaults = UserDefaults(suiteName: testDefaultsSuiteName)!

    static func main() throws {
        testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
        defer { testDefaults.removePersistentDomain(forName: testDefaultsSuiteName) }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpsmartTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try testDeduplication(in: temporaryDirectory)
        try testPersistence(in: temporaryDirectory)
        try testLimits(in: temporaryDirectory)
        try testRemoveAndClear(in: temporaryDirectory)
        try testSearchFiltering()
        try testThumbnailProvider()
        try testLegacyHistoryCompatibility(in: temporaryDirectory)
        try testDeduplicationUsesLatestSourceApplication(in: temporaryDirectory)
        try testPinBehavior(in: temporaryDirectory)
        try testPinnedEntriesSurviveLimitsAndClear(in: temporaryDirectory)
        try testPinnedFieldLegacyCompatibility(in: temporaryDirectory)
        try testRetentionPreferences(in: temporaryDirectory)
        try testExpiredEntries(in: temporaryDirectory)
        try testAdaptivePreviewSizing()
        try testShortcutDefaultsAndValidation()
        try testShortcutPersistenceAndReset()
        try testShortcutResetSwapAndNavigationPreset()
        try testShortcutMatcherContexts()
        try testInvalidShortcutPersistenceFallsBackToDefaults()
        try testPinboardLifecycle(in: temporaryDirectory)
        try testPinboardEntryPersistence(in: temporaryDirectory)
        try testPinboardReordering(in: temporaryDirectory)
        try testPinboardNameValidation(in: temporaryDirectory)
        print("All cpsmart core tests passed.")
    }

    private static func testAdaptivePreviewSizing() throws {
        // 负坐标副屏不应改变尺寸计算；算法只能依赖相对边界。
        let primaryVisible = NSRect(x: 0, y: 0, width: 1440, height: 860)
        let secondaryVisible = NSRect(x: -1440, y: 120, width: 1440, height: 860)
        let primarySource = NSRect(x: 120, y: 130, width: 204, height: 150)
        let secondarySource = NSRect(x: -1320, y: 250, width: 204, height: 150)
        let primaryLimits = AdaptivePreviewSizing.limits(
            visibleFrame: primaryVisible,
            sourceFrame: primarySource
        )
        let secondaryLimits = AdaptivePreviewSizing.limits(
            visibleFrame: secondaryVisible,
            sourceFrame: secondarySource
        )
        try require(
            primaryLimits.maximumWidth == secondaryLimits.maximumWidth
                && primaryLimits.maximumHeight == secondaryLimits.maximumHeight,
            "adaptive preview sizing depended on the screen origin"
        )

        let font = NSFont.systemFont(ofSize: 13.5)
        let shortText = AdaptivePreviewSizing.textSize(
            for: "一小段文本",
            font: font,
            visibleFrame: primaryVisible,
            sourceFrame: primarySource
        )
        let longText = AdaptivePreviewSizing.textSize(
            for: Array(repeating: "这是一段需要滚动显示的长文本。", count: 180).joined(separator: "\n"),
            font: font,
            visibleFrame: primaryVisible,
            sourceFrame: primarySource
        )
        try require(
            shortText.width < longText.width && shortText.height < longText.height,
            "long text did not receive a larger preview than short text"
        )
        try require(
            longText.width <= primaryLimits.maximumWidth
                && longText.height <= primaryLimits.maximumHeight,
            "long text preview exceeded the screen-derived limits"
        )

        let naturalImage = AdaptivePreviewSizing.imageSize(
            pixelSize: NSSize(width: 490, height: 159),
            visibleFrame: primaryVisible,
            sourceFrame: primarySource
        )
        try require(
            naturalImage.width == 514 && naturalImage.height == 231,
            "small image was unexpectedly enlarged or distorted"
        )

        let largeImage = AdaptivePreviewSizing.imageSize(
            pixelSize: NSSize(width: 6000, height: 4000),
            visibleFrame: primaryVisible,
            sourceFrame: primarySource
        )
        try require(
            largeImage.width <= primaryLimits.maximumWidth
                && largeImage.height <= primaryLimits.maximumHeight,
            "large image preview exceeded the screen-derived limits"
        )

        let smallScreen = NSRect(x: 0, y: 0, width: 360, height: 420)
        let smallScreenSource = NSRect(x: 20, y: 40, width: 200, height: 120)
        let constrained = AdaptivePreviewSizing.textSize(
            for: String(repeating: "内容 ", count: 1_000),
            font: font,
            visibleFrame: smallScreen,
            sourceFrame: smallScreenSource
        )
        try require(
            constrained.width <= smallScreen.width - 48
                && constrained.height <= smallScreen.height - 48,
            "adaptive preview did not respect a small screen's safe bounds"
        )

        let secondaryQuickLookFrame = AdaptivePreviewSizing.centeredQuickLookFrame(
            panelSize: NSSize(width: 816, height: 816),
            visibleFrame: secondaryVisible
        )
        try require(
            secondaryVisible.insetBy(dx: 24, dy: 24).contains(secondaryQuickLookFrame),
            "Quick Look frame escaped the negative-origin secondary display"
        )
        try require(
            secondaryQuickLookFrame.midX == secondaryVisible.midX
                && secondaryQuickLookFrame.midY == secondaryVisible.midY,
            "Quick Look frame was not centered on the selected display"
        )
    }

    private static func testDeduplication(in directory: URL) throws {
        let URL = directory.appendingPathComponent("deduplication.json")
        let store = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        store.add(.text("first"), at: Date(timeIntervalSince1970: 1))
        store.add(.text("second"), at: Date(timeIntervalSince1970: 2))
        store.add(.text("first"), at: Date(timeIntervalSince1970: 3))

        try require(store.entries.count == 2, "duplicate entry was not removed")
        try require(
            store.entries.map(\.payload) == [.text("first"), .text("second")],
            "duplicate entry was not promoted"
        )
        try require(
            store.entries.first?.createdAt == Date(timeIntervalSince1970: 3),
            "promoted entry timestamp was not refreshed"
        )
    }

    private static func testPinboardLifecycle(in directory: URL) throws {
        let URL = directory.appendingPathComponent("pinboard-lifecycle.json")
        let store = PinboardStore(fileURL: URL)
        let board = try requireValue(
            store.create(name: " 常用命令 ", color: .red),
            "valid pinboard was not created"
        )
        try require(board.name == "常用命令", "pinboard name was not trimmed")

        try require(store.rename(id: board.id, to: "开发命令"), "pinboard was not renamed")
        store.setColor(id: board.id, color: .blue)

        let reloaded = PinboardStore(fileURL: URL)
        try require(
            reloaded.boards.first?.name == "开发命令"
                && reloaded.boards.first?.color == .blue,
            "pinboard metadata did not persist"
        )

        reloaded.removeBoard(id: board.id)
        try require(
            PinboardStore(fileURL: URL).boards.isEmpty,
            "deleted pinboard was restored after reload"
        )
    }

    private static func testPinboardEntryPersistence(in directory: URL) throws {
        let URL = directory.appendingPathComponent("pinboard-entries.json")
        let store = PinboardStore(fileURL: URL)
        let board = try requireValue(
            store.create(name: "回复", color: .green),
            "pinboard was not created"
        )
        let historyEntry = ClipboardEntry(
            payload: .text("常用回复"),
            createdAt: Date(timeIntervalSince1970: 1),
            sourceAppName: "备忘录",
            sourceAppBundleID: "com.apple.Notes",
            isPinned: true
        )
        let firstFavorite = try requireValue(
            store.add(historyEntry, to: board.id),
            "history entry was not added to pinboard"
        )
        try require(firstFavorite.id != historyEntry.id, "pinboard did not create an independent snapshot")
        try require(firstFavorite.isPinned != true, "history pin state leaked into pinboard")

        let duplicateFavorite = store.add(historyEntry, to: board.id)
        try require(
            store.boards.first?.entries.count == 1,
            "adding the same payload created duplicate favorites"
        )
        try require(
            duplicateFavorite?.id == firstFavorite.id,
            "adding an existing favorite replaced or reordered its snapshot"
        )

        let reloaded = PinboardStore(fileURL: URL)
        let reloadedEntry = try requireValue(
            reloaded.boards.first?.entries.first,
            "pinboard entry did not persist"
        )
        try require(
            reloadedEntry.payload == historyEntry.payload
                && reloadedEntry.sourceAppBundleID == historyEntry.sourceAppBundleID,
            "pinboard snapshot lost payload or source metadata"
        )

        reloaded.removeEntry(id: reloadedEntry.id, from: board.id)
        try require(
            PinboardStore(fileURL: URL).boards.first?.entries.isEmpty == true,
            "removed favorite was restored after reload"
        )
    }

    private static func testPinboardNameValidation(in directory: URL) throws {
        let URL = directory.appendingPathComponent("pinboard-name-validation.json")
        let store = PinboardStore(fileURL: URL)
        try require(
            store.create(name: " \n ", color: .gray) == nil,
            "blank pinboard name was accepted"
        )
        let longName = String(repeating: "名", count: 40)
        let board = try requireValue(
            store.create(name: longName, color: .purple),
            "long pinboard name was rejected instead of normalized"
        )
        try require(board.name.count == 30, "long pinboard name was not capped at 30 characters")
        try require(
            !store.rename(id: board.id, to: "   "),
            "blank pinboard rename was accepted"
        )
    }

    private static func testPinboardReordering(in directory: URL) throws {
        let URL = directory.appendingPathComponent("pinboard-reordering.json")
        let store = PinboardStore(fileURL: URL)
        let board = try requireValue(
            store.create(name: "有序命令", color: .orange),
            "pinboard was not created"
        )
        store.add(ClipboardEntry(payload: .text("one")), to: board.id)
        store.add(ClipboardEntry(payload: .text("two")), to: board.id)
        let three = try requireValue(
            store.add(ClipboardEntry(payload: .text("three")), to: board.id),
            "third pinboard entry was not added"
        )
        try require(
            store.boards.first?.entries.map(\.payload) == [
                .text("three"), .text("two"), .text("one")
            ],
            "pinboard seed order was unexpected"
        )

        store.moveEntry(id: three.id, toInsertionIndex: 3, in: board.id)
        try require(
            store.boards.first?.entries.map(\.payload) == [
                .text("two"), .text("one"), .text("three")
            ],
            "moving a favorite to the end used the wrong insertion index"
        )
        try require(
            PinboardStore(fileURL: URL).boards.first?.entries.map(\.payload) == [
                .text("two"), .text("one"), .text("three")
            ],
            "reordered favorites did not persist"
        )

        store.moveEntry(id: three.id, toInsertionIndex: 0, in: board.id)
        try require(
            store.boards.first?.entries.map(\.payload) == [
                .text("three"), .text("two"), .text("one")
            ],
            "moving a favorite to the beginning failed"
        )
    }

    private static func testPersistence(in directory: URL) throws {
        let URL = directory.appendingPathComponent("persistence.json")
        let store = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        store.add(.text("hello"))
        store.add(.image(data: Data([1, 2, 3]), pasteboardType: "public.png"))
        store.add(.files(["/tmp/a.txt", "/tmp/b.txt"]))

        let reloaded = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        try require(
            reloaded.entries.map(\.payload) == store.entries.map(\.payload),
            "supported payloads did not round-trip"
        )
    }

    private static func testLimits(in directory: URL) throws {
        let countURL = directory.appendingPathComponent("count-limit.json")
        let countLimited = HistoryStore(
            fileURL: countURL,
            maximumEntryCount: 2,
            maximumStorageBytes: 100,
            userDefaults: testDefaults
        )
        countLimited.add(.text("one"))
        countLimited.add(.text("two"))
        countLimited.add(.text("three"))
        try require(
            countLimited.entries.map(\.payload) == [.text("three"), .text("two")],
            "entry count limit did not discard the oldest entry"
        )

        let sizeURL = directory.appendingPathComponent("size-limit.json")
        let sizeLimited = HistoryStore(
            fileURL: sizeURL,
            maximumEntryCount: 10,
            maximumStorageBytes: 5,
            userDefaults: testDefaults
        )
        sizeLimited.add(.text("1234"))
        sizeLimited.add(.text("abc"))
        try require(
            sizeLimited.entries.map(\.payload) == [.text("abc")],
            "storage limit did not discard the oldest entry"
        )
    }

    private static func testRemoveAndClear(in directory: URL) throws {
        let URL = directory.appendingPathComponent("remove-clear.json")
        let store = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        let removable = store.add(.text("remove"))
        store.add(.text("keep"))
        store.remove(id: removable.id)
        try require(
            HistoryStore(fileURL: URL, userDefaults: testDefaults).entries.map(\.payload)
                == [.text("keep")],
            "removed entry was restored after reload"
        )

        store.clear()
        try require(
            HistoryStore(fileURL: URL, userDefaults: testDefaults).entries.isEmpty,
            "cleared history was restored after reload"
        )
    }

    private static func testSearchFiltering() throws {
        let quickFox = ClipboardEntry(payload: .text("The Quick Brown Fox"))
        let quickDog = ClipboardEntry(payload: .text("The quick brown dog"))
        let accented = ClipboardEntry(payload: .text("Résumé ABC"))
        let chinese = ClipboardEntry(payload: .text("你好，剪贴板"))
        let image = ClipboardEntry(
            payload: .image(data: Data([1]), pasteboardType: "public.png")
        )
        let file = ClipboardEntry(payload: .files(["/tmp/reports/年度总结.pdf"]))
        let entries = [quickFox, quickDog, accented, chinese, image, file]

        try require(
            SearchFilter.filter(entries, query: " \n\t ") == entries,
            "blank search query did not return the original entries"
        )
        try require(
            SearchFilter.filter(entries, query: "quick fox") == [quickFox],
            "multiple search terms were not combined with AND"
        )
        try require(
            SearchFilter.filter(entries, query: "résumé abc") == [accented],
            "case-insensitive search did not match"
        )
        try require(
            SearchFilter.filter(entries, query: "resume ＡＢＣ") == [accented],
            "diacritic- or width-insensitive search did not match"
        )
        try require(
            SearchFilter.filter(entries, query: "剪贴板") == [chinese],
            "Chinese search text did not match"
        )
        try require(
            SearchFilter.filter(entries, query: "图片") == [image]
                && SearchFilter.filter(entries, query: "IMAGE") == [image],
            "image entries were not searchable by their Chinese and English labels"
        )
        try require(
            SearchFilter.filter(entries, query: "年度总结.pdf") == [file],
            "file name search did not match its path"
        )
    }

    private static func testThumbnailProvider() throws {
        let provider = ThumbnailProvider()
        let imageEntry = ClipboardEntry(
            payload: .image(data: try makePNGData(), pasteboardType: "public.png")
        )

        let first = try waitForThumbnail(from: provider, entry: imageEntry)
        try require(first != nil, "generated PNG did not produce a thumbnail")
        if let first {
            try require(
                max(first.size.width, first.size.height) <= 480,
                "thumbnail exceeded the configured maximum pixel size"
            )
        }

        let second = try waitForThumbnail(from: provider, entry: imageEntry)
        try require(first === second, "second thumbnail request did not return the cached image")

        let textResult = try waitForThumbnail(
            from: provider,
            entry: ClipboardEntry(payload: .text("not an image"))
        )
        try require(textResult == nil, "non-image entry unexpectedly produced a thumbnail")
    }

    private static func testLegacyHistoryCompatibility(in directory: URL) throws {
        let URL = directory.appendingPathComponent("legacy-history.json")
        let legacyEntry = LegacyClipboardEntry(
            id: UUID(),
            payload: .text("legacy"),
            createdAt: Date(timeIntervalSince1970: 123)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacyEntry]).write(to: URL)

        let reloaded = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        try require(reloaded.entries.count == 1, "old history JSON could not be decoded")
        try require(
            reloaded.entries.first?.sourceAppName == nil
                && reloaded.entries.first?.sourceAppBundleID == nil,
            "missing source application fields did not decode as nil"
        )
    }

    private static func testDeduplicationUsesLatestSourceApplication(in directory: URL) throws {
        let URL = directory.appendingPathComponent("source-application-deduplication.json")
        let store = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        store.add(
            .text("same payload"),
            sourceAppName: "Old App",
            sourceAppBundleID: "com.example.old",
            at: Date(timeIntervalSince1970: 1)
        )
        store.add(
            .text("same payload"),
            sourceAppName: "New App",
            sourceAppBundleID: "com.example.new",
            at: Date(timeIntervalSince1970: 2)
        )

        try require(store.entries.count == 1, "source application changed payload deduplication")
        try require(
            store.entries.first?.sourceAppName == "New App"
                && store.entries.first?.sourceAppBundleID == "com.example.new",
            "deduplicated entry did not keep the latest source application"
        )

        let reloaded = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        try require(
            reloaded.entries.first?.sourceAppName == "New App"
                && reloaded.entries.first?.sourceAppBundleID == "com.example.new",
            "source application fields did not persist"
        )
    }

    private static func testPinBehavior(in directory: URL) throws {
        let URL = directory.appendingPathComponent("pin-behavior.json")
        let store = HistoryStore(
            fileURL: URL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            userDefaults: testDefaults
        )
        let oldest = store.add(.text("oldest"), at: Date(timeIntervalSince1970: 1))
        let middle = store.add(.text("middle"), at: Date(timeIntervalSince1970: 2))
        store.add(.text("newest"), at: Date(timeIntervalSince1970: 3))

        store.togglePin(id: oldest.id)
        store.togglePin(id: middle.id)
        try require(
            store.entries.map(\.payload) == [
                .text("middle"),
                .text("oldest"),
                .text("newest")
            ],
            "pinned and unpinned groups were not sorted newest-first"
        )

        store.add(
            .text("oldest"),
            sourceAppName: "Latest Source",
            sourceAppBundleID: "com.example.latest",
            at: Date(timeIntervalSince1970: 4)
        )
        try require(store.entries.count == 3, "pin state changed payload deduplication")
        try require(
            store.entries.first?.payload == .text("oldest")
                && store.entries.first?.isPinned == true,
            "deduplicated entry did not inherit pin state"
        )
        try require(
            store.entries.first?.sourceAppBundleID == "com.example.latest",
            "deduplicated pinned entry did not keep the latest source application"
        )
    }

    private static func testPinnedEntriesSurviveLimitsAndClear(in directory: URL) throws {
        let countURL = directory.appendingPathComponent("pinned-count-limit.json")
        let countLimited = HistoryStore(
            fileURL: countURL,
            maximumEntryCount: 2,
            maximumStorageBytes: 10_000,
            userDefaults: testDefaults
        )
        let pinned = countLimited.add(.text("pinned"), at: Date(timeIntervalSince1970: 1))
        countLimited.togglePin(id: pinned.id)
        countLimited.add(.text("discarded"), at: Date(timeIntervalSince1970: 2))
        countLimited.add(.text("retained"), at: Date(timeIntervalSince1970: 3))
        try require(
            countLimited.entries.map(\.payload) == [.text("pinned"), .text("retained")],
            "entry count limit evicted a pinned entry"
        )

        let sizeURL = directory.appendingPathComponent("pinned-size-limit.json")
        let sizeLimited = HistoryStore(
            fileURL: sizeURL,
            maximumEntryCount: 10,
            maximumStorageBytes: 5,
            userDefaults: testDefaults
        )
        let sizePinned = sizeLimited.add(.text("1234"))
        sizeLimited.togglePin(id: sizePinned.id)
        sizeLimited.add(.text("abcd"))
        try require(
            sizeLimited.entries.map(\.payload) == [.text("1234")],
            "storage limit evicted a pinned entry"
        )

        countLimited.clear()
        try require(
            countLimited.entries.map(\.payload) == [.text("pinned")],
            "clear removed a pinned entry"
        )
        countLimited.clearAll()
        try require(countLimited.entries.isEmpty, "clearAll did not remove pinned entries")
    }

    private static func testPinnedFieldLegacyCompatibility(in directory: URL) throws {
        let URL = directory.appendingPathComponent("legacy-without-pin.json")
        let legacyEntry = LegacyClipboardEntryWithSource(
            id: UUID(),
            payload: .text("legacy pin"),
            createdAt: Date(timeIntervalSince1970: 456),
            sourceAppName: "Legacy App",
            sourceAppBundleID: "com.example.legacy"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacyEntry]).write(to: URL)

        let reloaded = HistoryStore(
            fileURL: URL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            userDefaults: testDefaults
        )
        try require(reloaded.entries.count == 1, "history JSON without isPinned did not decode")
        try require(
            reloaded.entries.first?.isPinned == nil,
            "missing isPinned field did not decode as nil"
        )
    }

    private static func testRetentionPreferences(in directory: URL) throws {
        let defaultSuiteName = "cpsmartTests-retentionDefaults-\(UUID().uuidString)"
        let defaultSettings = UserDefaults(suiteName: defaultSuiteName)!
        defer { defaultSettings.removePersistentDomain(forName: defaultSuiteName) }

        let defaultStore = HistoryStore(
            fileURL: directory.appendingPathComponent("retention-defaults.json"),
            userDefaults: defaultSettings
        )
        try require(
            defaultStore.maximumEntryCount == 200
                && defaultStore.maximumStorageBytes == 25 * 1_024 * 1_024
                && defaultStore.keepDays == 0,
            "retention defaults no longer match the previous behavior"
        )
        defaultStore.add(.text("old but unlimited"), at: Date(timeIntervalSince1970: 1))
        try require(
            defaultStore.entries.count == 1,
            "default unlimited retention removed an old entry"
        )

        let customSuiteName = "cpsmartTests-retentionCustom-\(UUID().uuidString)"
        let customSettings = UserDefaults(suiteName: customSuiteName)!
        defer { customSettings.removePersistentDomain(forName: customSuiteName) }
        customSettings.set(2, forKey: "maximumEntryCount")
        customSettings.set(1, forKey: "maximumStorageMB")
        customSettings.set(0, forKey: "keepDays")

        let countLimited = HistoryStore(
            fileURL: directory.appendingPathComponent("retention-custom-count.json"),
            userDefaults: customSettings
        )
        countLimited.add(.text("one"))
        countLimited.add(.text("two"))
        countLimited.add(.text("three"))
        try require(
            countLimited.entries.map(\.payload) == [.text("three"), .text("two")],
            "UserDefaults maximumEntryCount was not applied"
        )
        try require(
            countLimited.maximumStorageBytes == 1 * 1_024 * 1_024,
            "UserDefaults maximumStorageMB was not converted to bytes"
        )

        customSettings.set(10, forKey: "maximumEntryCount")
        let sizeLimited = HistoryStore(
            fileURL: directory.appendingPathComponent("retention-custom-size.json"),
            userDefaults: customSettings
        )
        sizeLimited.add(.image(
            data: Data(repeating: 1, count: 700_000),
            pasteboardType: "public.png"
        ))
        sizeLimited.add(.image(
            data: Data(repeating: 2, count: 700_000),
            pasteboardType: "public.png"
        ))
        try require(sizeLimited.entries.count == 1, "UserDefaults storage limit was not applied")
    }

    private static func testExpiredEntries(in directory: URL) throws {
        let referenceDate = Date(timeIntervalSince1970: 100 * 24 * 60 * 60)
        let suiteName = "cpsmartTests-expiration-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }
        settings.set(7, forKey: "keepDays")

        let store = HistoryStore(
            fileURL: directory.appendingPathComponent("expiration.json"),
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            userDefaults: settings,
            now: { referenceDate }
        )
        store.add(
            .text("recent"),
            at: referenceDate.addingTimeInterval(-6 * 24 * 60 * 60)
        )
        store.add(
            .text("expired"),
            at: referenceDate.addingTimeInterval(-8 * 24 * 60 * 60)
        )
        try require(
            store.entries.map(\.payload) == [.text("recent")],
            "entry older than keepDays was not removed"
        )

        let pinnedURL = directory.appendingPathComponent("pinned-expiration.json")
        let seedStore = HistoryStore(
            fileURL: pinnedURL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            keepDays: 0,
            userDefaults: testDefaults
        )
        let oldPinned = seedStore.add(
            .text("permanent"),
            at: referenceDate.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        seedStore.togglePin(id: oldPinned.id)

        let reloaded = HistoryStore(
            fileURL: pinnedURL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            userDefaults: settings,
            now: { referenceDate }
        )
        try require(
            reloaded.entries.first?.payload == .text("permanent")
                && reloaded.entries.first?.isPinned == true,
            "keepDays removed a pinned entry"
        )
    }

    private static func testShortcutDefaultsAndValidation() throws {
        let suiteName = "cpsmartTests-shortcutDefaults-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }
        let shortcuts = ShortcutStore(userDefaults: settings)

        try require(
            shortcuts.displayString(for: .toggleHistory) == "⇧⌘V",
            "default global shortcut display changed"
        )
        try require(
            shortcuts.bindings(for: .pasteSelection).count == 2,
            "Return and keypad Enter defaults were not both preserved"
        )
        try require(
            shortcuts.displayString(for: .addToPinboard) == "⌘D",
            "default pinboard shortcut display changed"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_UpArrow)),
                for: .selectPrevious
            ) == nil,
            "an unmodified arrow key was rejected"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_ANSI_A)),
                for: .selectPrevious
            ) == .requiresModifier,
            "an unmodified text key was accepted"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_ANSI_A), modifiers: [.shift]),
                for: .toggleHistory
            ) == .globalRequiresModifier,
            "a shift-only global shortcut was accepted"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command]),
                for: .toggleQuickLook
            ) == .reservedByApplication,
            "Command-Q was accepted as a configurable shortcut"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_ANSI_C), modifiers: [.command]),
                for: .toggleQuickLook
            ) == .reservedByApplication,
            "standard Command-C editing shortcut was accepted"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_RightArrow)),
                for: .selectPrevious
            ) == .conflictsWith(.selectNext),
            "duplicate shortcut conflict was not detected"
        )
    }

    private static func testShortcutPersistenceAndReset() throws {
        let suiteName = "cpsmartTests-shortcutPersistence-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }

        let up = ShortcutGesture(keyCode: UInt16(kVK_UpArrow))
        let shortcuts = ShortcutStore(userDefaults: settings)
        try require(
            shortcuts.set(up, for: .selectPrevious) == nil,
            "valid shortcut override was rejected"
        )
        try require(shortcuts.hasCustomizations, "customization state was not recorded")

        let reloaded = ShortcutStore(userDefaults: settings)
        try require(
            reloaded.bindings(for: .selectPrevious) == [up],
            "shortcut override did not persist"
        )
        let left = ShortcutGesture(keyCode: UInt16(kVK_LeftArrow))
        try require(
            reloaded.set(left, for: .selectPrevious) == nil
                && !reloaded.hasCustomizations
                && settings.data(forKey: ShortcutStore.defaultsKey) == nil,
            "recording the single default binding did not clear its override"
        )
        try require(
            reloaded.set(up, for: .selectPrevious) == nil,
            "shortcut could not be customized again after returning to default"
        )
        reloaded.resetToDefaults()
        try require(
            !reloaded.hasCustomizations
                && reloaded.primaryBinding(for: .selectPrevious).keyCode == UInt16(kVK_LeftArrow)
                && settings.data(forKey: ShortcutStore.defaultsKey) == nil,
            "reset did not remove persisted overrides and restore defaults"
        )
    }

    private static func testShortcutResetSwapAndNavigationPreset() throws {
        let suiteName = "cpsmartTests-shortcutEditing-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }
        let shortcuts = ShortcutStore(userDefaults: settings)

        let left = ShortcutGesture(keyCode: UInt16(kVK_LeftArrow))
        let right = ShortcutGesture(keyCode: UInt16(kVK_RightArrow))
        let up = ShortcutGesture(keyCode: UInt16(kVK_UpArrow))
        let down = ShortcutGesture(keyCode: UInt16(kVK_DownArrow))

        try require(
            shortcuts.swap(
                .selectPrevious,
                with: .selectNext,
                requestedGesture: right
            ) == nil
                && shortcuts.primaryBinding(for: .selectPrevious) == right
                && shortcuts.primaryBinding(for: .selectNext) == left
                && shortcuts.customizationCount == 2,
            "conflicting navigation shortcuts were not swapped atomically"
        )
        try require(
            shortcuts.validateReset(for: .selectPrevious) == .conflictsWith(.selectNext),
            "single-action reset did not detect a conflict with the current bindings"
        )
        try require(
            shortcuts.applyNavigationPreset(previous: up, next: down) == nil
                && shortcuts.primaryBinding(for: .selectPrevious) == up
                && shortcuts.primaryBinding(for: .selectNext) == down,
            "vertical navigation preset was not applied atomically"
        )
        try require(
            shortcuts.resetToDefault(.selectPrevious) == nil
                && shortcuts.primaryBinding(for: .selectPrevious) == left
                && !shortcuts.isCustomized(.selectPrevious)
                && shortcuts.isCustomized(.selectNext),
            "single-action reset did not restore only the requested shortcut"
        )

        let globalGesture = shortcuts.primaryBinding(for: .toggleHistory)
        try require(
            shortcuts.validateSwap(
                .selectPrevious,
                with: .toggleHistory,
                requestedGesture: globalGesture
            ) == .globalRequiresModifier,
            "swap allowed an unmodified key to become the global shortcut"
        )
    }

    private static func testShortcutMatcherContexts() throws {
        let suiteName = "cpsmartTests-shortcutMatcher-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }
        let shortcuts = ShortcutStore(userDefaults: settings)
        let matcher = ShortcutMatcher(store: shortcuts)

        let left = makeKeyEvent(keyCode: UInt16(kVK_LeftArrow), characters: "")
        try require(
            matcher.action(for: left, context: .browsing) == .selectPrevious,
            "left arrow did not resolve in browsing context"
        )
        try require(
            matcher.action(for: left, context: .searching) == nil,
            "left arrow intercepted search field navigation"
        )

        let tab = makeKeyEvent(keyCode: UInt16(kVK_Tab), characters: "\t")
        try require(
            matcher.action(for: tab, context: .searching) == .toggleSearchFocus,
            "Tab did not resolve in search context"
        )
        try require(
            matcher.action(for: tab, context: .composingSearchText) == nil,
            "Tab intercepted input method composition"
        )

        let commandOne = makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_1),
            modifiers: [.command],
            characters: "1"
        )
        try require(
            matcher.action(for: commandOne, context: .composingSearchText) == .filterAll,
            "explicit Command shortcut stopped working during input method composition"
        )

        let commandD = makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_D),
            modifiers: [.command],
            characters: "d"
        )
        try require(
            matcher.action(for: commandD, context: .browsing) == .addToPinboard
                && matcher.action(for: commandD, context: .composingSearchText) == .addToPinboard,
            "pinboard shortcut did not resolve in supported contexts"
        )

        let space = makeKeyEvent(keyCode: UInt16(kVK_Space), characters: " ")
        try require(
            matcher.action(for: space, context: .browsing) == .toggleQuickLook,
            "Space did not resolve in browsing context"
        )
        try require(
            matcher.action(for: space, context: .searching) == nil,
            "Space was intercepted while typing in the search field"
        )

        let optionCommandP = makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_P),
            modifiers: [.option, .command],
            characters: "p"
        )
        try require(
            matcher.action(for: optionCommandP, context: .browsing) == nil,
            "shortcut matching ignored extra modifiers"
        )

        let optionUp = ShortcutGesture(keyCode: UInt16(kVK_UpArrow), modifiers: [.option])
        try require(
            shortcuts.set(optionUp, for: .togglePin) == nil,
            "Option-arrow custom shortcut was rejected"
        )
        let optionUpEvent = makeKeyEvent(
            keyCode: UInt16(kVK_UpArrow),
            modifiers: [.option],
            characters: ""
        )
        try require(
            matcher.action(for: optionUpEvent, context: .browsing) == .togglePin
                && matcher.action(for: optionUpEvent, context: .searching) == nil,
            "custom management shortcut intercepted search field word navigation"
        )
    }

    private static func testInvalidShortcutPersistenceFallsBackToDefaults() throws {
        let suiteName = "cpsmartTests-invalidShortcuts-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }
        let invalidJSON = """
        {"version":1,"bindings":{"selectPrevious":[{"keyCode":0,"modifiersRawValue":0}]}}
        """
        settings.set(Data(invalidJSON.utf8), forKey: ShortcutStore.defaultsKey)

        let shortcuts = ShortcutStore(userDefaults: settings)
        try require(
            shortcuts.primaryBinding(for: .selectPrevious).keyCode == UInt16(kVK_LeftArrow),
            "invalid persisted shortcut did not fall back to the default"
        )
    }

    private static func makeKeyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private static func makePNGData() throws -> Data {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let data = representation.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "cpsmartCoreTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "could not generate test PNG"]
            )
        }
        return data
    }

    private static func waitForThumbnail(
        from provider: ThumbnailProvider,
        entry: ClipboardEntry
    ) throws -> NSImage? {
        var result: NSImage?
        var didComplete = false
        provider.thumbnail(for: entry) { image in
            result = image
            didComplete = true
        }

        let deadline = Date().addingTimeInterval(3)
        while !didComplete && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        try require(didComplete, "thumbnail callback did not arrive on the main run loop")
        return result
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw NSError(
                domain: "cpsmartCoreTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw NSError(
                domain: "cpsmartCoreTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return value
    }

    private struct LegacyClipboardEntry: Codable {
        let id: UUID
        let payload: ClipboardPayload
        let createdAt: Date
    }

    private struct LegacyClipboardEntryWithSource: Codable {
        let id: UUID
        let payload: ClipboardPayload
        let createdAt: Date
        let sourceAppName: String?
        let sourceAppBundleID: String?
    }
}
