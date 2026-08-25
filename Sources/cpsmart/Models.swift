import Foundation

enum ClipboardPayload: Codable, Equatable {
    case text(String)
    case image(data: Data, pasteboardType: String)
    case files([String])

    var estimatedSize: Int {
        switch self {
        case .text(let text):
            return text.utf8.count
        case .image(let data, _):
            return data.count
        case .files(let paths):
            return paths.reduce(0) { $0 + $1.utf8.count }
        }
    }

    var searchableText: String {
        switch self {
        case .text(let text):
            return text
        case .image:
            return "图片 image"
        case .files(let paths):
            return paths.joined(separator: " ")
        }
    }
}

struct ClipboardEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let payload: ClipboardPayload
    let createdAt: Date
    let sourceAppName: String?
    let sourceAppBundleID: String?
    let isPinned: Bool?

    init(
        id: UUID = UUID(),
        payload: ClipboardPayload,
        createdAt: Date = Date(),
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        isPinned: Bool? = nil
    ) {
        self.id = id
        self.payload = payload
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.isPinned = isPinned
    }
}
