import Foundation

enum SearchFilter {
    /// Filters entries by whitespace-separated search terms.
    /// Every term must match the payload's searchable text.
    static func filter(_ entries: [ClipboardEntry], query: String) -> [ClipboardEntry] {
        let terms = query.split(whereSeparator: { $0.isWhitespace })
        guard !terms.isEmpty else { return entries }

        let options: String.CompareOptions = [
            .caseInsensitive,
            .diacriticInsensitive,
            .widthInsensitive
        ]

        return entries.filter { entry in
            terms.allSatisfy { term in
                entry.payload.searchableText.range(
                    of: String(term),
                    options: options
                ) != nil
            }
        }
    }
}
