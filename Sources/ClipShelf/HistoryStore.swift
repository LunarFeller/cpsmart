import Foundation

final class HistoryStore {
    private(set) var entries: [ClipboardEntry] = []

    let maximumEntryCount: Int
    let maximumStorageBytes: Int
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL? = nil,
        maximumEntryCount: Int = 200,
        maximumStorageBytes: Int = 25 * 1_024 * 1_024,
        fileManager: FileManager = .default
    ) {
        self.maximumEntryCount = maximumEntryCount
        self.maximumStorageBytes = maximumStorageBytes
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        load()
    }

    @discardableResult
    func add(_ payload: ClipboardPayload, at date: Date = Date()) -> ClipboardEntry {
        entries.removeAll { $0.payload == payload }
        let entry = ClipboardEntry(payload: payload, createdAt: date)
        entries.insert(entry, at: 0)
        trimToLimits()
        save()
        return entry
    }

    func promote(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id || $0.payload == entry.payload }
        entries.insert(
            ClipboardEntry(id: entry.id, payload: entry.payload, createdAt: Date()),
            at: 0
        )
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func trimToLimits() {
        if entries.count > maximumEntryCount {
            entries.removeLast(entries.count - maximumEntryCount)
        }

        var total = entries.reduce(0) { $0 + $1.payload.estimatedSize }
        while total > maximumStorageBytes, let last = entries.last {
            total -= last.payload.estimatedSize
            entries.removeLast()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            entries = try Self.decoder.decode([ClipboardEntry].self, from: data)
            trimToLimits()
        } catch {
            // Keep a damaged history file for possible manual recovery and start clean.
            entries = []
        }
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try Self.encoder.encode(entries)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            NSLog("ClipShelf could not save clipboard history: %@", error.localizedDescription)
        }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("ClipShelf", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
