import AppKit
import Carbon
import Foundation

enum PinboardShortcutCommand: Equatable {
    case selectSource(index: Int)
    case cycle(offset: Int)
}

enum PinboardShortcutRouting {
    private static let directSourceIndexes: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 0,
        UInt16(kVK_ANSI_2): 1,
        UInt16(kVK_ANSI_3): 2,
        UInt16(kVK_ANSI_4): 3,
        UInt16(kVK_ANSI_5): 4,
        UInt16(kVK_ANSI_6): 5,
        UInt16(kVK_ANSI_7): 6,
        UInt16(kVK_ANSI_8): 7,
        UInt16(kVK_ANSI_9): 8
    ]

    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> PinboardShortcutCommand? {
        let normalized = modifiers.intersection([.command, .option, .control, .shift])
        if normalized == [.command, .option],
           let sourceIndex = directSourceIndexes[keyCode] {
            return .selectSource(index: sourceIndex)
        }
        guard keyCode == UInt16(kVK_Tab), normalized.contains(.control) else { return nil }
        if normalized == [.control] {
            return .cycle(offset: 1)
        }
        if normalized == [.control, .shift] {
            return .cycle(offset: -1)
        }
        return nil
    }

    static func cycledSourceIndex(
        currentIndex: Int,
        sourceCount: Int,
        offset: Int
    ) -> Int? {
        guard sourceCount > 0, sourceCount > currentIndex, currentIndex >= 0 else { return nil }
        return (currentIndex + offset % sourceCount + sourceCount) % sourceCount
    }
}

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
