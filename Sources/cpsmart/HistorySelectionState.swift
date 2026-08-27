import Foundation

struct HistorySelectionState<ID: Hashable>: Equatable {
    private(set) var activeID: ID?
    private(set) var selectedIDs: Set<ID> = []
    private(set) var anchorID: ID?

    mutating func reset() {
        activeID = nil
        selectedIDs = []
        anchorID = nil
    }

    func activeIndex(in orderedIDs: [ID]) -> Int? {
        guard let activeID else { return nil }
        return orderedIDs.firstIndex(of: activeID)
    }

    func selectedIndexes(in orderedIDs: [ID]) -> Set<Int> {
        Set(orderedIDs.indices.filter { selectedIDs.contains(orderedIDs[$0]) })
    }

    @discardableResult
    mutating func selectSingle(_ id: ID) -> Bool {
        let changed = activeID != id || selectedIDs != [id]
        activeID = id
        selectedIDs = [id]
        anchorID = id
        return changed
    }

    mutating func extendSelection(to id: ID, in orderedIDs: [ID]) {
        guard let targetIndex = orderedIDs.firstIndex(of: id) else { return }
        let resolvedAnchorID = anchorID.flatMap { orderedIDs.contains($0) ? $0 : nil }
            ?? activeID.flatMap { orderedIDs.contains($0) ? $0 : nil }
            ?? id
        guard let anchorIndex = orderedIDs.firstIndex(of: resolvedAnchorID) else { return }
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        activeID = id
        selectedIDs = Set(range.map { orderedIDs[$0] })
        anchorID = resolvedAnchorID
    }

    mutating func selectAll(in orderedIDs: [ID]) {
        guard !orderedIDs.isEmpty else {
            reset()
            return
        }
        let resolvedActiveID = activeID.flatMap { orderedIDs.contains($0) ? $0 : nil }
            ?? orderedIDs[0]
        activeID = resolvedActiveID
        selectedIDs = Set(orderedIDs)
        if anchorID.map({ selectedIDs.contains($0) }) != true {
            anchorID = resolvedActiveID
        }
    }

    /// Returns true when the target was added. A single remaining item cannot be toggled off.
    @discardableResult
    mutating func toggle(_ id: ID, in orderedIDs: [ID]) -> Bool {
        guard orderedIDs.contains(id) else { return false }
        selectedIDs.formIntersection(orderedIDs)
        let isRemoving = selectedIDs.contains(id)
        if isRemoving, selectedIDs.count > 1 {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        anchorID = id
        if selectedIDs.contains(id) {
            activeID = id
        } else {
            activeID = orderedIDs.first(where: { selectedIDs.contains($0) })
        }
        return !isRemoving
    }

    mutating func replaceSelection(
        _ ids: Set<ID>,
        activeID: ID,
        anchorID: ID? = nil,
        in orderedIDs: [ID]
    ) {
        let visibleIDs = Set(orderedIDs)
        var retainedIDs = ids.intersection(visibleIDs)
        guard visibleIDs.contains(activeID) else { return }
        // 活动项必须属于选区；调用方给出不一致输入时，以活动项为准修复状态。
        retainedIDs.insert(activeID)
        self.activeID = activeID
        selectedIDs = retainedIDs
        if let anchorID, retainedIDs.contains(anchorID) {
            self.anchorID = anchorID
        } else if self.anchorID.map({ retainedIDs.contains($0) }) != true {
            self.anchorID = activeID
        }
    }

    mutating func reconcile(
        with orderedIDs: [ID],
        preferredID: ID? = nil,
        fallbackIndex: Int
    ) {
        guard !orderedIDs.isEmpty else {
            reset()
            return
        }

        let visibleIDs = Set(orderedIDs)
        let retainedSelection = selectedIDs.intersection(visibleIDs)
        let resolvedActiveID: ID
        if let preferredID, visibleIDs.contains(preferredID) {
            resolvedActiveID = preferredID
        } else if let activeID, retainedSelection.contains(activeID) {
            resolvedActiveID = activeID
        } else if let retainedID = orderedIDs.first(where: { retainedSelection.contains($0) }) {
            resolvedActiveID = retainedID
        } else {
            let safeFallbackIndex = min(max(fallbackIndex, 0), orderedIDs.count - 1)
            resolvedActiveID = orderedIDs[safeFallbackIndex]
        }

        activeID = resolvedActiveID
        if let preferredID, visibleIDs.contains(preferredID) {
            selectedIDs = [preferredID]
        } else if !retainedSelection.isEmpty {
            selectedIDs = retainedSelection
        } else {
            selectedIDs = [resolvedActiveID]
        }
        if anchorID.map({ selectedIDs.contains($0) }) != true {
            anchorID = resolvedActiveID
        }
    }
}
