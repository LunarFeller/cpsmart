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

    func removeEntry(id: UUID, from boardID: UUID) {
        guard let boardIndex = boards.firstIndex(where: { $0.id == boardID }) else { return }
        boards[boardIndex].entries.removeAll { $0.id == id }
        save()
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
