import AppKit
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
        print("All cpsmart core tests passed.")
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
