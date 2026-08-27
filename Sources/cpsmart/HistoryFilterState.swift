import Foundation

enum HistoryContentTypeFilter: Int, CaseIterable, Equatable {
    case all = 0
    case text
    case image
    case files

    func matches(_ entry: ClipboardEntry) -> Bool {
        switch (self, entry.payload) {
        case (.all, _),
             (.text, .text),
             (.image, .image),
             (.files, .files):
            return true
        default:
            return false
        }
    }
}

struct HistoryFilterState: Equatable {
    private(set) var query = ""
    private(set) var type: HistoryContentTypeFilter = .all

    var isFiltering: Bool {
        !query.isEmpty || type != .all
    }

    var allowsPinboardReordering: Bool {
        !isFiltering
    }

    mutating func reset() {
        query = ""
        type = .all
    }

    mutating func updateQuery(_ query: String) {
        self.query = query
    }

    mutating func updateType(rawValue: Int) {
        type = HistoryContentTypeFilter(rawValue: rawValue) ?? .all
    }

    func apply(to entries: [ClipboardEntry]) -> [ClipboardEntry] {
        SearchFilter.filter(entries, query: query)
            .filter { type.matches($0) }
    }
}
