import AppKit
import Carbon
import Foundation

struct PackageSmokeSnapshot {
    let visibleEntryIDs: [UUID]
    let pinboardIDs: [UUID]
    let selectedPinboardID: UUID?
    let selectedIndex: Int
    let selectedEntryIDs: Set<UUID>
    let hasPendingDeletionUndo: Bool
    let query: String
    let historyEntryCount: Int
    let isSearchFieldFocused: Bool
    let isPreviewSessionActive: Bool
    let isAdaptivePreviewVisible: Bool
    let isQuickLookVisible: Bool
    let isWindowVisible: Bool
}

struct PackageSmokeHost {
    let window: () -> NSWindow?
    let snapshot: () -> PackageSmokeSnapshot
    let selectIndex: (Int) -> Void
    let postCardClick: (Int, NSEvent.ModifierFlags, Int, @escaping (Bool) -> Void) -> Void
    let postKey: (UInt16, NSEvent.ModifierFlags, String, @escaping () -> Void) -> Void
    let installChooseObserver: (@escaping (UUID) -> Void) -> (() -> Void)
    let installPasteStub: (@escaping () -> Void) -> Void
}

private struct PackageSmokeRect: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: NSRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }
}

private struct PackageSmokeValidationReport: Codable {
    let expectedScreenIndex: Int
    let actualScreenIndex: Int?
    let screenCount: Int
    let screenFrame: PackageSmokeRect?
    let visibleFrame: PackageSmokeRect?
    let windowFrame: PackageSmokeRect?
    let scaleFactors: [CGFloat]
    let plainMouseSelectionsPassed: Bool
    let commandMouseSelectionsPassed: Bool
    let shiftMouseSelectionCount: Int
    let selectAllSelectionCount: Int
    let shiftKeyboardSelectionCount: Int
    let pinboardShortcutsPassed: Bool
    let undoDeletePassed: Bool
    let searchPassed: Bool
    let previewPassed: Bool
    let doubleClickPastePassed: Bool
    let failures: [String]
    let passed: Bool
}

final class PackageSmokeValidationDriver {
    private let expectedScreenIndex: Int
    private let reportURL: URL
    private let host: PackageSmokeHost
    private let completion: () -> Void
    private var pinboardShortcutsPassed = false

    init(
        expectedScreenIndex: Int,
        reportURL: URL,
        host: PackageSmokeHost,
        completion: @escaping () -> Void
    ) {
        self.expectedScreenIndex = expectedScreenIndex
        self.reportURL = reportURL
        self.host = host
        self.completion = completion
    }

    func run() {
        var failures: [String] = []
        let screens = NSScreen.screens
        let actualScreen = host.window()?.screen
        let actualScreenIndex = actualScreen.flatMap { screen in
            screens.firstIndex(where: { $0 === screen })
        }
        if screens.count < 2 {
            failures.append("only \(screens.count) screen was available")
        }
        if actualScreenIndex != expectedScreenIndex {
            failures.append(
                "window appeared on screen \(actualScreenIndex.map(String.init) ?? "nil") instead of \(expectedScreenIndex)"
            )
        }
        if !screens.contains(where: { $0.frame.minX < 0 || $0.frame.minY < 0 }) {
            failures.append("no negative-origin display was present")
        }
        if Set(screens.map(\.backingScaleFactor)).count < 2 {
            failures.append("displays did not exercise mixed scale factors")
        }
        if let windowFrame = host.window()?.frame,
           let visibleFrame = actualScreen?.visibleFrame,
           !visibleFrame.contains(windowFrame) {
            failures.append("history window escaped the target screen visible frame")
        }

        let itemCount = host.snapshot().visibleEntryIDs.count
        guard itemCount >= 5 else {
            failures.append("demo data did not contain enough cards")
            writeReport(
                screens: screens,
                actualScreen: actualScreen,
                actualScreenIndex: actualScreenIndex,
                plainMouseSelectionsPassed: false,
                commandMouseSelectionsPassed: false,
                shiftMouseSelectionCount: 0,
                selectAllSelectionCount: 0,
                shiftKeyboardSelectionCount: 0,
                undoDeletePassed: false,
                searchPassed: false,
                previewPassed: false,
                doubleClickPastePassed: false,
                failures: failures
            )
            return
        }

        runPinboardShortcutFlow { [self] pinboardPassed in
            pinboardShortcutsPassed = pinboardPassed
            if !pinboardPassed {
                failures.append("pinboard direct or cycle shortcuts did not select the expected source")
            }
            runCommandSelectionFlow(itemCount: itemCount) { [self] commandPassed in
                if !commandPassed {
                    failures.append("Command-click add/remove did not keep selection and active copy in sync")
                }
                runPlainClickFlow(itemCount: itemCount) { [self] plainPassed in
                    if !plainPassed {
                        failures.append("plain mouse selection failed for first, middle, or last card")
                    }
                    host.postCardClick(0, [], 1) { [self] _ in
                        host.postCardClick(itemCount - 1, [.shift], 1) { [self] _ in
                            let shiftMouseCount = host.snapshot().selectedEntryIDs.count
                            if shiftMouseCount != itemCount {
                                failures.append(
                                    "Shift-click selected \(shiftMouseCount) of \(itemCount) cards"
                                )
                            }
                            host.selectIndex(itemCount / 2)
                            host.postKey(UInt16(kVK_ANSI_A), [.command], "a") { [self] in
                                let selectAllCount = host.snapshot().selectedEntryIDs.count
                                if selectAllCount != itemCount {
                                    failures.append(
                                        "Command-A selected \(selectAllCount) of \(itemCount) cards"
                                    )
                                }
                                runShiftKeyboardAndRemainingFlow(
                                    itemCount: itemCount,
                                    screens: screens,
                                    actualScreen: actualScreen,
                                    actualScreenIndex: actualScreenIndex,
                                    plainPassed: plainPassed,
                                    commandPassed: commandPassed,
                                    shiftMouseCount: shiftMouseCount,
                                    selectAllCount: selectAllCount,
                                    failures: failures
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func runPinboardShortcutFlow(completion: @escaping (Bool) -> Void) {
        let initialSnapshot = host.snapshot()
        guard initialSnapshot.pinboardIDs.count >= 2 else {
            completion(false)
            return
        }
        let firstBoardID = initialSnapshot.pinboardIDs[0]
        let secondBoardID = initialSnapshot.pinboardIDs[1]

        var checks: [Bool] = []

        func record(_ passed: Bool, _ name: String) {
            checks.append(passed)
            if !passed {
                NSLog("cpsmart package smoke pinboard shortcut check failed: %@", name)
            }
        }

        func finishOnRecent() {
            host.postKey(UInt16(kVK_ANSI_1), [.command, .option], "1") { [self] in
                let recentSnapshot = host.snapshot()
                record(
                    recentSnapshot.selectedPinboardID == nil
                        && recentSnapshot.visibleEntryIDs.count == recentSnapshot.historyEntryCount,
                    "direct recent"
                )
                completion(checks.allSatisfy { $0 })
            }
        }

        func verifyPreviewSwitch() {
            host.postKey(UInt16(kVK_ANSI_1), [.command, .option], "1") { [self] in
                host.selectIndex(0)
                host.postKey(UInt16(kVK_Space), [], " ") { [self] in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
                        let opened = host.snapshot().isPreviewSessionActive
                        host.postKey(UInt16(kVK_ANSI_2), [.command, .option], "2") { [self] in
                            // NSPopover 关闭带动画；会话状态会立即结束，但视觉状态需要等动画完成。
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                                let switched = host.snapshot()
                                record(
                                    opened
                                        && switched.selectedPinboardID == firstBoardID
                                        && !switched.isPreviewSessionActive
                                        && !switched.isAdaptivePreviewVisible
                                        && !switched.isQuickLookVisible,
                                    "switch while previewing"
                                )
                                finishOnRecent()
                            }
                        }
                    }
                }
            }
        }

        func verifySearchSwitch() {
            host.postKey(UInt16(kVK_Tab), [], "\t") { [self] in
                let focused = host.snapshot().isSearchFieldFocused
                host.postKey(UInt16(kVK_ANSI_G), [], "g") { [self] in
                    let typed = host.snapshot().query == "g"
                    host.postKey(UInt16(kVK_ANSI_3), [.command, .option], "3") { [self] in
                        let switched = host.snapshot()
                        record(
                            focused
                                && typed
                                && switched.selectedPinboardID == secondBoardID
                                && switched.query.isEmpty
                                && !switched.isSearchFieldFocused,
                            "switch while searching"
                        )
                        verifyPreviewSwitch()
                    }
                }
            }
        }

        host.postKey(UInt16(kVK_ANSI_2), [.command, .option], "2") { [self] in
            record(host.snapshot().selectedPinboardID == firstBoardID, "direct first board")
            host.postKey(UInt16(kVK_Tab), [.control], "\t") { [self] in
                record(host.snapshot().selectedPinboardID == secondBoardID, "cycle first to second")
                host.postKey(UInt16(kVK_Tab), [.control], "\t") { [self] in
                    record(host.snapshot().selectedPinboardID == nil, "cycle last to recent")
                    host.postKey(UInt16(kVK_Tab), [.control, .shift], "\t") { [self] in
                        record(host.snapshot().selectedPinboardID == secondBoardID, "cycle recent to last")
                        host.postKey(UInt16(kVK_Tab), [.control, .shift], "\t") { [self] in
                            record(host.snapshot().selectedPinboardID == firstBoardID, "cycle second to first")
                            verifySearchSwitch()
                        }
                    }
                }
            }
        }
    }

    private func runPlainClickFlow(itemCount: Int, completion: @escaping (Bool) -> Void) {
        let indexes = [0, itemCount / 2, itemCount - 1]
        var results: [Bool] = []

        func run(at position: Int) {
            guard indexes.indices.contains(position) else {
                completion(results.count == indexes.count && results.allSatisfy { $0 })
                return
            }
            let index = indexes[position]
            host.postCardClick(index, [], 1) { [self] didPost in
                let snapshot = host.snapshot()
                results.append(
                    didPost
                        && snapshot.selectedIndex == index
                        && snapshot.selectedEntryIDs == [snapshot.visibleEntryIDs[index]]
                )
                run(at: position + 1)
            }
        }
        run(at: 0)
    }

    private func runCommandSelectionFlow(itemCount: Int, completion: @escaping (Bool) -> Void) {
        let firstIndex = 0
        let secondIndex = itemCount / 2
        let initialIDs = host.snapshot().visibleEntryIDs
        let firstID = initialIDs[firstIndex]
        let secondID = initialIDs[secondIndex]
        var chosenIDs: [UUID] = []
        let restoreChoose = host.installChooseObserver { chosenIDs.append($0) }

        func finish(_ passed: Bool) {
            restoreChoose()
            completion(passed)
        }

        host.postCardClick(firstIndex, [], 1) { [self] firstPosted in
            host.postCardClick(secondIndex, [.command], 1) { [self] addPosted in
                var snapshot = host.snapshot()
                let addPassed = addPosted
                    && snapshot.selectedEntryIDs == Set([firstID, secondID])
                    && snapshot.selectedIndex == secondIndex
                    && chosenIDs.last == secondID
                let chooseCountBeforeRemovingNonActive = chosenIDs.count
                host.postCardClick(firstIndex, [.command], 1) { [self] removeNonActivePosted in
                    snapshot = host.snapshot()
                    let removeNonActivePassed = removeNonActivePosted
                        && snapshot.selectedEntryIDs == [secondID]
                        && snapshot.selectedIndex == secondIndex
                        && chosenIDs.count == chooseCountBeforeRemovingNonActive
                    host.postCardClick(firstIndex, [.command], 1) { [self] readdPosted in
                        snapshot = host.snapshot()
                        let readdPassed = readdPosted
                            && snapshot.selectedEntryIDs == Set([firstID, secondID])
                            && snapshot.selectedIndex == firstIndex
                            && chosenIDs.last == firstID
                        let chooseCountBeforeRemovingActive = chosenIDs.count
                        host.postCardClick(firstIndex, [.command], 1) { [self] removeActivePosted in
                            snapshot = host.snapshot()
                            let removeActivePassed = removeActivePosted
                                && snapshot.selectedEntryIDs == [secondID]
                                && snapshot.selectedIndex == secondIndex
                                && chosenIDs.count == chooseCountBeforeRemovingActive + 1
                                && chosenIDs.last == secondID
                            finish(
                                firstPosted
                                    && addPassed
                                    && removeNonActivePassed
                                    && readdPassed
                                    && removeActivePassed
                            )
                        }
                    }
                }
            }
        }
    }

    private func runShiftKeyboardAndRemainingFlow(
        itemCount: Int,
        screens: [NSScreen],
        actualScreen: NSScreen?,
        actualScreenIndex: Int?,
        plainPassed: Bool,
        commandPassed: Bool,
        shiftMouseCount: Int,
        selectAllCount: Int,
        failures: [String]
    ) {
        var failures = failures
        host.selectIndex(2)
        host.postKey(UInt16(kVK_RightArrow), [.shift], "") { [self] in
            let shiftSnapshot = host.snapshot()
            let shiftKeyboardCount = shiftSnapshot.selectedEntryIDs.count
            if shiftKeyboardCount != 2 || shiftSnapshot.selectedIndex != 3 {
                failures.append("Shift-arrow did not extend to the adjacent card")
            }
            let deletedEntryID = shiftSnapshot.visibleEntryIDs[1]
            host.selectIndex(1)
            host.postKey(UInt16(kVK_Delete), [.command], "\u{8}") { [self] in
                let deletionSnapshot = host.snapshot()
                let deletionPassed = deletionSnapshot.visibleEntryIDs.count == itemCount - 1
                    && !deletionSnapshot.visibleEntryIDs.contains(deletedEntryID)
                    && deletionSnapshot.hasPendingDeletionUndo
                host.postKey(UInt16(kVK_ANSI_Z), [.command], "z") { [self] in
                    let undoSnapshot = host.snapshot()
                    let undoPassed = deletionPassed
                        && undoSnapshot.visibleEntryIDs.count == itemCount
                        && undoSnapshot.visibleEntryIDs.contains(deletedEntryID)
                        && !undoSnapshot.hasPendingDeletionUndo
                    if !undoPassed {
                        failures.append("Command-Z did not restore the deleted card")
                    }
                    runContentFlow { [self] searchPassed, previewPassed in
                        if !searchPassed {
                            failures.append("search focus, typing, or clearing failed")
                        }
                        if !previewPassed {
                            failures.append("Space preview did not open and close")
                        }
                        var didRequestPaste = false
                        host.installPasteStub { didRequestPaste = true }
                        host.postCardClick(0, [], 2) { [self] didPost in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [self] in
                                let doubleClickPassed = didPost
                                    && didRequestPaste
                                    && !host.snapshot().isWindowVisible
                                if !doubleClickPassed {
                                    failures.append(
                                        "double-click did not request paste and close the window"
                                    )
                                }
                                writeReport(
                                    screens: screens,
                                    actualScreen: actualScreen,
                                    actualScreenIndex: actualScreenIndex,
                                    plainMouseSelectionsPassed: plainPassed,
                                    commandMouseSelectionsPassed: commandPassed,
                                    shiftMouseSelectionCount: shiftMouseCount,
                                    selectAllSelectionCount: selectAllCount,
                                    shiftKeyboardSelectionCount: shiftKeyboardCount,
                                    undoDeletePassed: undoPassed,
                                    searchPassed: searchPassed,
                                    previewPassed: previewPassed,
                                    doubleClickPastePassed: doubleClickPassed,
                                    failures: failures
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func runContentFlow(completion: @escaping (Bool, Bool) -> Void) {
        host.selectIndex(0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
            host.postKey(UInt16(kVK_Space), [], " ") { [self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
                    let openSnapshot = host.snapshot()
                    let previewOpened = openSnapshot.isPreviewSessionActive
                        && (openSnapshot.isAdaptivePreviewVisible || openSnapshot.isQuickLookVisible)
                    host.postKey(UInt16(kVK_Space), [], " ") { [self] in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                            let closedSnapshot = host.snapshot()
                            let previewPassed = previewOpened
                                && !closedSnapshot.isPreviewSessionActive
                                && !closedSnapshot.isAdaptivePreviewVisible
                                && !closedSnapshot.isQuickLookVisible
                            runSearchFlow { searchPassed in
                                completion(searchPassed, previewPassed)
                            }
                        }
                    }
                }
            }
        }
    }

    private func runSearchFlow(completion: @escaping (Bool) -> Void) {
        host.postKey(UInt16(kVK_Tab), [], "\t") { [self] in
            let didFocusSearch = host.snapshot().isSearchFieldFocused
            let keyEvents: [(UInt16, String)] = [
                (UInt16(kVK_ANSI_G), "g"),
                (UInt16(kVK_ANSI_I), "i"),
                (UInt16(kVK_ANSI_T), "t")
            ]

            func typeCharacter(at position: Int) {
                guard keyEvents.indices.contains(position) else {
                    let filteredSnapshot = host.snapshot()
                    let didFilter = filteredSnapshot.query == "git"
                        && !filteredSnapshot.visibleEntryIDs.isEmpty
                        && filteredSnapshot.visibleEntryIDs.count < filteredSnapshot.historyEntryCount
                    host.postKey(UInt16(kVK_Escape), [], "\u{1b}") { [self] in
                        let clearedSnapshot = host.snapshot()
                        completion(
                            didFocusSearch
                                && didFilter
                                && clearedSnapshot.query.isEmpty
                                && clearedSnapshot.visibleEntryIDs.count
                                    == clearedSnapshot.historyEntryCount
                        )
                    }
                    return
                }
                let event = keyEvents[position]
                host.postKey(event.0, [], event.1) {
                    typeCharacter(at: position + 1)
                }
            }
            typeCharacter(at: 0)
        }
    }

    private func writeReport(
        screens: [NSScreen],
        actualScreen: NSScreen?,
        actualScreenIndex: Int?,
        plainMouseSelectionsPassed: Bool,
        commandMouseSelectionsPassed: Bool,
        shiftMouseSelectionCount: Int,
        selectAllSelectionCount: Int,
        shiftKeyboardSelectionCount: Int,
        undoDeletePassed: Bool,
        searchPassed: Bool,
        previewPassed: Bool,
        doubleClickPastePassed: Bool,
        failures: [String]
    ) {
        let report = PackageSmokeValidationReport(
            expectedScreenIndex: expectedScreenIndex,
            actualScreenIndex: actualScreenIndex,
            screenCount: screens.count,
            screenFrame: actualScreen.map { PackageSmokeRect($0.frame) },
            visibleFrame: actualScreen.map { PackageSmokeRect($0.visibleFrame) },
            windowFrame: host.window().map { PackageSmokeRect($0.frame) },
            scaleFactors: screens.map(\.backingScaleFactor),
            plainMouseSelectionsPassed: plainMouseSelectionsPassed,
            commandMouseSelectionsPassed: commandMouseSelectionsPassed,
            shiftMouseSelectionCount: shiftMouseSelectionCount,
            selectAllSelectionCount: selectAllSelectionCount,
            shiftKeyboardSelectionCount: shiftKeyboardSelectionCount,
            pinboardShortcutsPassed: pinboardShortcutsPassed,
            undoDeletePassed: undoDeletePassed,
            searchPassed: searchPassed,
            previewPassed: previewPassed,
            doubleClickPastePassed: doubleClickPastePassed,
            failures: failures,
            passed: failures.isEmpty
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: reportURL, options: .atomic)
        } catch {
            NSLog("cpsmart could not write package smoke report: %@", error.localizedDescription)
        }
        completion()
    }
}
