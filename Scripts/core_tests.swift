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
}
