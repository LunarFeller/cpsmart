import Foundation

enum HistoryPreviewPresentation: Equatable {
    case none
    case adaptive
    case quickLook
    case unavailable
}

struct HistoryPreviewSessionState: Equatable {
    private(set) var isActive = false
    private(set) var presentation: HistoryPreviewPresentation = .none

    @discardableResult
    mutating func start() -> Bool {
        guard !isActive else { return false }
        isActive = true
        presentation = .none
        return true
    }

    mutating func recordAdaptiveShown() {
        guard isActive else { return }
        presentation = .adaptive
    }

    mutating func recordQuickLookShown() {
        guard isActive else { return }
        presentation = .quickLook
    }

    mutating func recordUnavailable() {
        guard isActive else { return }
        presentation = .unavailable
    }

    mutating func recordPresentationClosed() {
        guard isActive else {
            presentation = .none
            return
        }
        presentation = .none
    }

    mutating func end() {
        isActive = false
        presentation = .none
    }
}

final class QuickLookPreviewStore {
    private let directory: URL
    private(set) var previewURL: URL?

    init(directory: URL? = nil) {
        self.directory = directory
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cpsmart-quicklook", isDirectory: true)
    }

    deinit {
        clear()
    }

    @discardableResult
    func prepare(for entry: ClipboardEntry) -> URL? {
        clear()
        switch entry.payload {
        case .files:
            return nil
        case .image(let data, let pasteboardType):
            let fileExtension = pasteboardType == "public.tiff" ? "tiff" : "png"
            previewURL = write(
                data: data,
                filename: "\(entry.id.uuidString).\(fileExtension)"
            )
        case .text(let text):
            previewURL = write(
                data: Data(text.utf8),
                filename: "\(entry.id.uuidString).txt"
            )
        }
        return previewURL
    }

    func clear() {
        previewURL = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(data: Data, filename: String) -> URL? {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
