import Foundation

final class HistoryStore {
    private(set) var entries: [ClipboardEntry] = []

    let maximumEntryCount: Int
    let maximumStorageBytes: Int
    let keepDays: Int
    private let fileURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        fileURL: URL? = nil,
        maximumEntryCount: Int? = nil,
        maximumStorageBytes: Int? = nil,
        keepDays: Int? = nil,
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.maximumEntryCount = max(
            0,
            maximumEntryCount ?? Self.integerValue(
                forKey: "maximumEntryCount",
                defaultValue: 200,
                userDefaults: userDefaults
            )
        )
        if let maximumStorageBytes {
            self.maximumStorageBytes = max(0, maximumStorageBytes)
        } else {
            let configuredMB = Self.integerValue(
                forKey: "maximumStorageMB",
                defaultValue: 25,
                userDefaults: userDefaults
            )
            let clampedMB = min(max(0, configuredMB), Int.max / (1_024 * 1_024))
            self.maximumStorageBytes = clampedMB * 1_024 * 1_024
        }
        self.keepDays = max(
            0,
            keepDays ?? Self.integerValue(
                forKey: "keepDays",
                defaultValue: 0,
                userDefaults: userDefaults
            )
        )
        self.fileManager = fileManager
        self.now = now
        let resolvedFileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.fileURL = resolvedFileURL
        if fileURL == nil {
            Self.migrateLegacyHistoryIfNeeded(to: resolvedFileURL, fileManager: fileManager)
        }
        load()
    }

    @discardableResult
    func add(
        _ payload: ClipboardPayload,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        at date: Date = Date()
    ) -> ClipboardEntry {
        let shouldRemainPinned = entries.first(where: { $0.payload == payload })?.isPinned == true
        entries.removeAll { $0.payload == payload }
        let entry = ClipboardEntry(
            payload: payload,
            createdAt: date,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID,
            isPinned: shouldRemainPinned ? true : nil
        )
        entries.insert(entry, at: 0)
        trimToLimits()
        save()
        return entry
    }

    @discardableResult
    func promote(id: UUID) -> Bool {
        guard let entry = entries.first(where: { $0.id == id }) else { return false }
        entries.removeAll { $0.id == entry.id || $0.payload == entry.payload }
        entries.insert(
            ClipboardEntry(
                id: entry.id,
                payload: entry.payload,
                createdAt: entry.createdAt,
                lastUsedAt: now(),
                sourceAppName: entry.sourceAppName,
                sourceAppBundleID: entry.sourceAppBundleID,
                isPinned: entry.isPinned
            ),
            at: 0
        )
        trimToLimits()
        save()
        return true
    }

    func togglePin(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        entries[index] = ClipboardEntry(
            id: entry.id,
            payload: entry.payload,
            createdAt: entry.createdAt,
            lastUsedAt: entry.lastUsedAt,
            sourceAppName: entry.sourceAppName,
            sourceAppBundleID: entry.sourceAppBundleID,
            isPinned: entry.isPinned == true ? false : true
        )
        sortEntries()
        trimToLimits()
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll { $0.isPinned != true }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    private func trimToLimits() {
        sortEntries()

        if keepDays > 0,
           let cutoff = Calendar.current.date(
               byAdding: .day,
               value: -keepDays,
               to: now()
           ) {
            entries.removeAll { $0.isPinned != true && $0.recencyDate < cutoff }
        }

        while entries.count > maximumEntryCount,
              let removalIndex = entries.lastIndex(where: { $0.isPinned != true }) {
            entries.remove(at: removalIndex)
        }

        var total = entries.reduce(0) { $0 + $1.payload.estimatedSize }
        while total > maximumStorageBytes,
              let removalIndex = entries.lastIndex(where: { $0.isPinned != true }) {
            total -= entries[removalIndex].payload.estimatedSize
            entries.remove(at: removalIndex)
        }
    }

    private func sortEntries() {
        entries.sort { lhs, rhs in
            let lhsIsPinned = lhs.isPinned == true
            let rhsIsPinned = rhs.isPinned == true
            if lhsIsPinned != rhsIsPinned {
                return lhsIsPinned
            }
            return lhs.recencyDate > rhs.recencyDate
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
            NSLog("cpsmart could not save clipboard history: %@", error.localizedDescription)
        }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("cpsmart", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }

    private static func integerValue(
        forKey key: String,
        defaultValue: Int,
        userDefaults: UserDefaults
    ) -> Int {
        guard userDefaults.object(forKey: key) != nil else { return defaultValue }
        return userDefaults.integer(forKey: key)
    }

    private static func migrateLegacyHistoryIfNeeded(to destination: URL, fileManager: FileManager) {
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let legacyFile = applicationSupport
            .appendingPathComponent("ClipShelf", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
        guard fileManager.fileExists(atPath: legacyFile.path) else { return }

        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.copyItem(at: legacyFile, to: destination)
        } catch {
            NSLog("cpsmart could not migrate clipboard history: %@", error.localizedDescription)
        }
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
