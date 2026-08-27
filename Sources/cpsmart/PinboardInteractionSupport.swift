import AppKit
import Foundation

struct PinboardSourceState: Equatable {
    private(set) var selectedPinboardID: UUID?

    var isHistory: Bool {
        selectedPinboardID == nil
    }

    mutating func selectHistory() {
        selectedPinboardID = nil
    }

    @discardableResult
    mutating func selectPinboard(_ id: UUID, from pinboards: [Pinboard]) -> Pinboard? {
        guard let board = pinboards.first(where: { $0.id == id }) else {
            selectedPinboardID = nil
            return nil
        }
        selectedPinboardID = id
        return board
    }

    @discardableResult
    mutating func reconcile(with pinboards: [Pinboard]) -> Pinboard? {
        guard let selectedPinboardID else { return nil }
        guard let board = pinboards.first(where: { $0.id == selectedPinboardID }) else {
            self.selectedPinboardID = nil
            return nil
        }
        return board
    }
}

enum PinboardInteractionSupport {
    static func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(30))
    }

    static func addedCount(entries: [ClipboardEntry], to board: Pinboard) -> Int {
        let existingPayloads = board.entries.map(\.payload)
        return entries.filter { !existingPayloads.contains($0.payload) }.count
    }

    static func boardID(from representedObject: Any?) -> UUID? {
        guard let rawID = representedObject as? String else { return nil }
        return UUID(uuidString: rawID)
    }

    static func boardColor(from representedObject: Any?) -> (UUID, PinboardColor)? {
        guard let rawValue = representedObject as? String else { return nil }
        let parts = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let id = UUID(uuidString: parts[0]),
              let color = PinboardColor(rawValue: parts[1]) else { return nil }
        return (id, color)
    }
}

struct PinboardDragDescriptor: Equatable {
    let entryID: UUID
    let sourcePinboardID: UUID?

    static let pasteboardType = NSPasteboard.PasteboardType("com.cpsmart.pinboard-entry")

    func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        var value = entryID.uuidString
        if let sourcePinboardID {
            value += "|\(sourcePinboardID.uuidString)"
        }
        item.setString(value, forType: Self.pasteboardType)
        return item
    }

    static func read(from pasteboard: NSPasteboard) -> PinboardDragDescriptor? {
        guard let rawValue = pasteboard.string(forType: pasteboardType) else { return nil }
        let parts = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
        guard let entryID = UUID(uuidString: parts[0]) else { return nil }
        let sourcePinboardID: UUID?
        if parts.count == 2 {
            guard let parsedSourceID = UUID(uuidString: parts[1]) else { return nil }
            sourcePinboardID = parsedSourceID
        } else {
            sourcePinboardID = nil
        }
        return PinboardDragDescriptor(entryID: entryID, sourcePinboardID: sourcePinboardID)
    }
}

enum PinboardDragRules {
    static func sourceOperation(sourcePinboardID: UUID?) -> NSDragOperation {
        sourcePinboardID == nil ? .copy : .move
    }

    static func canBeginDrag(
        selectedItemCount: Int,
        itemIsVisible: Bool,
        sourcePinboardID: UUID?,
        allowsPinboardReordering: Bool
    ) -> Bool {
        guard selectedItemCount == 1, itemIsVisible else { return false }
        return sourcePinboardID == nil || allowsPinboardReordering
    }

    static func reorderDescriptor(
        from pasteboard: NSPasteboard,
        targetPinboardID: UUID?,
        allowsPinboardReordering: Bool
    ) -> PinboardDragDescriptor? {
        guard allowsPinboardReordering,
              let targetPinboardID,
              let descriptor = PinboardDragDescriptor.read(from: pasteboard),
              descriptor.sourcePinboardID == targetPinboardID else { return nil }
        return descriptor
    }
}
