import AppKit
import Foundation

@main
struct CoreTests {
    static func main() throws {
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
        print("All cpsmart core tests passed.")
    }

    private static func testDeduplication(in directory: URL) throws {
        let URL = directory.appendingPathComponent("deduplication.json")
        let store = HistoryStore(fileURL: URL)
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
        let store = HistoryStore(fileURL: URL)
        store.add(.text("hello"))
        store.add(.image(data: Data([1, 2, 3]), pasteboardType: "public.png"))
        store.add(.files(["/tmp/a.txt", "/tmp/b.txt"]))

        let reloaded = HistoryStore(fileURL: URL)
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
            maximumStorageBytes: 100
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
            maximumStorageBytes: 5
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
        let store = HistoryStore(fileURL: URL)
        let removable = store.add(.text("remove"))
        store.add(.text("keep"))
        store.remove(id: removable.id)
        try require(
            HistoryStore(fileURL: URL).entries.map(\.payload) == [.text("keep")],
            "removed entry was restored after reload"
        )

        store.clear()
        try require(
            HistoryStore(fileURL: URL).entries.isEmpty,
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

        let reloaded = HistoryStore(fileURL: URL)
        try require(reloaded.entries.count == 1, "old history JSON could not be decoded")
        try require(
            reloaded.entries.first?.sourceAppName == nil
                && reloaded.entries.first?.sourceAppBundleID == nil,
            "missing source application fields did not decode as nil"
        )
    }

    private static func testDeduplicationUsesLatestSourceApplication(in directory: URL) throws {
        let URL = directory.appendingPathComponent("source-application-deduplication.json")
        let store = HistoryStore(fileURL: URL)
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

        let reloaded = HistoryStore(fileURL: URL)
        try require(
            reloaded.entries.first?.sourceAppName == "New App"
                && reloaded.entries.first?.sourceAppBundleID == "com.example.new",
            "source application fields did not persist"
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
}
