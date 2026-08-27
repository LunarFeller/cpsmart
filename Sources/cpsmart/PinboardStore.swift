import Foundation

final class PinboardStore {
    private(set) var boards: [Pinboard] = []

    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL? = nil,
        initialBoards: [Pinboard]? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        if let initialBoards {
            boards = initialBoards
        } else {
            load()
        }
    }

    @discardableResult
    func create(name: String, color: PinboardColor) -> Pinboard? {
        guard let name = Self.normalizedName(name) else { return nil }
        let board = Pinboard(name: name, color: color)
        boards.append(board)
        save()
        return board
    }

    @discardableResult
    func rename(id: UUID, to name: String) -> Bool {
        guard let name = Self.normalizedName(name),
              let index = boards.firstIndex(where: { $0.id == id }) else { return false }
        boards[index].name = name
        save()
        return true
    }

    func setColor(id: UUID, color: PinboardColor) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[index].color = color
        save()
    }

    func removeBoard(id: UUID) {
        boards.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    func add(_ entry: ClipboardEntry, to boardID: UUID) -> ClipboardEntry? {
        guard let boardIndex = boards.firstIndex(where: { $0.id == boardID }) else { return nil }

        if let existing = boards[boardIndex].entries.first(where: { $0.payload == entry.payload }) {
            return existing
        }

        let favorite = ClipboardEntry(
            payload: entry.payload,
            createdAt: Date(),
            sourceAppName: entry.sourceAppName,
            sourceAppBundleID: entry.sourceAppBundleID
        )
        boards[boardIndex].entries.insert(favorite, at: 0)
        save()
        return favorite
    }

    @discardableResult
    func add(_ entries: [ClipboardEntry], to boardID: UUID) -> Int {
        guard let boardIndex = boards.firstIndex(where: { $0.id == boardID }) else { return 0 }

        var knownPayloads = boards[boardIndex].entries.map(\.payload)
        var favorites: [ClipboardEntry] = []
        for entry in entries where !knownPayloads.contains(entry.payload) {
            knownPayloads.append(entry.payload)
            favorites.append(ClipboardEntry(
                payload: entry.payload,
                createdAt: Date(),
                sourceAppName: entry.sourceAppName,
                sourceAppBundleID: entry.sourceAppBundleID
            ))
        }
        guard !favorites.isEmpty else { return 0 }
        boards[boardIndex].entries.insert(contentsOf: favorites, at: 0)
        save()
        return favorites.count
    }

    func removeEntry(id: UUID, from boardID: UUID) {
        _ = removeEntries(ids: [id], from: boardID)
    }

    @discardableResult
    func removeEntries(ids: Set<UUID>, from boardID: UUID) -> [RemovedClipboardEntry] {
        guard !ids.isEmpty,
              let boardIndex = boards.firstIndex(where: { $0.id == boardID }) else { return [] }
        let removed = boards[boardIndex].entries.enumerated().compactMap { index, entry in
            ids.contains(entry.id) ? RemovedClipboardEntry(entry: entry, index: index) : nil
        }
        guard !removed.isEmpty else { return [] }
        boards[boardIndex].entries.removeAll { ids.contains($0.id) }
        save()
        return removed
    }

    @discardableResult
    func restoreEntries(_ removed: [RemovedClipboardEntry], to boardID: UUID) -> Int {
        guard !removed.isEmpty,
              let boardIndex = boards.firstIndex(where: { $0.id == boardID }) else { return 0 }

        let restoredEntries = removed.map(\.entry)
        let restoredIDs = Set(restoredEntries.map(\.id))
        boards[boardIndex].entries.removeAll { existing in
            restoredIDs.contains(existing.id)
                || restoredEntries.contains(where: { $0.payload == existing.payload })
        }
        for removedEntry in removed.sorted(by: { $0.index < $1.index }) {
            let insertionIndex = min(max(removedEntry.index, 0), boards[boardIndex].entries.count)
            boards[boardIndex].entries.insert(removedEntry.entry, at: insertionIndex)
        }
        save()
        return removed.count
    }

    func moveEntry(id: UUID, toInsertionIndex insertionIndex: Int, in boardID: UUID) {
        guard let boardIndex = boards.firstIndex(where: { $0.id == boardID }),
              let sourceIndex = boards[boardIndex].entries.firstIndex(where: { $0.id == id }) else {
            return
        }

        let entry = boards[boardIndex].entries.remove(at: sourceIndex)
        let adjustedIndex = insertionIndex > sourceIndex ? insertionIndex - 1 : insertionIndex
        let destinationIndex = min(max(0, adjustedIndex), boards[boardIndex].entries.count)
        boards[boardIndex].entries.insert(entry, at: destinationIndex)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            boards = try Self.decoder.decode([Pinboard].self, from: data)
        } catch {
            boards = []
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
            let data = try Self.encoder.encode(boards)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            NSLog("cpsmart could not save pinboards: %@", error.localizedDescription)
        }
    }

    private static func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(30))
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("cpsmart", isDirectory: true)
            .appendingPathComponent("pinboards.json", isDirectory: false)
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
