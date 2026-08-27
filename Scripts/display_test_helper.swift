import AppKit
import CoreGraphics
import Foundation

private struct SmokeReport: Decodable {
    let expectedScreenIndex: Int
    let actualScreenIndex: Int?
    let screenCount: Int
    let scaleFactors: [CGFloat]
    let plainMouseSelectionsPassed: Bool
    let commandMouseSelectionsPassed: Bool
    let shiftMouseSelectionCount: Int
    let selectAllSelectionCount: Int
    let shiftKeyboardSelectionCount: Int
    let undoDeletePassed: Bool
    let searchPassed: Bool
    let previewPassed: Bool
    let doubleClickPastePassed: Bool
    let failures: [String]
    let passed: Bool
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count >= 2 else {
    fail("usage: display_test_helper.swift <count|environment|warp|verify>")
}

let screens = NSScreen.screens
switch CommandLine.arguments[1] {
case "count":
    print(screens.count)

case "environment":
    guard screens.count >= 2 else { fail("multi-display validation requires at least two screens") }
    guard screens.contains(where: { $0.frame.minX < 0 || $0.frame.minY < 0 }) else {
        fail("multi-display validation requires a negative-origin screen layout")
    }
    guard Set(screens.map(\.backingScaleFactor)).count >= 2 else {
        fail("multi-display validation requires mixed display scale factors")
    }
    for (index, screen) in screens.enumerated() {
        print(
            "screen[\(index)] frame=\(screen.frame) visible=\(screen.visibleFrame) scale=\(screen.backingScaleFactor)"
        )
    }

case "warp":
    guard CommandLine.arguments.count == 3,
          let index = Int(CommandLine.arguments[2]),
          screens.indices.contains(index) else {
        fail("warp requires a valid screen index")
    }
    let screen = screens[index]
    let cocoaPoint = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
    let quartzPoint = CGPoint(
        x: cocoaPoint.x,
        y: screens[0].frame.maxY - cocoaPoint.y
    )
    guard CGWarpMouseCursorPosition(quartzPoint) == .success else {
        fail("could not move the pointer to screen \(index)")
    }
    usleep(250_000)
    let actualPoint = NSEvent.mouseLocation
    guard screen.frame.contains(actualPoint) else {
        fail("pointer landed at \(actualPoint), outside screen \(index) frame \(screen.frame)")
    }
    print("pointer screen[\(index)] cocoa=\(actualPoint) quartz=\(quartzPoint)")

case "verify":
    guard CommandLine.arguments.count == 4,
          let expectedIndex = Int(CommandLine.arguments[3]) else {
        fail("verify requires a report path and expected screen index")
    }
    let reportURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let report: SmokeReport
    do {
        report = try JSONDecoder().decode(SmokeReport.self, from: Data(contentsOf: reportURL))
    } catch {
        fail("could not read smoke report: \(error.localizedDescription)")
    }
    guard report.expectedScreenIndex == expectedIndex,
          report.actualScreenIndex == expectedIndex,
          report.passed else {
        fail("screen \(expectedIndex) validation failed: \(report.failures.joined(separator: "; "))")
    }
    print(
        "screen[\(expectedIndex)] passed: screens=\(report.screenCount) scales=\(report.scaleFactors) mouse=\(report.plainMouseSelectionsPassed) commandClick=\(report.commandMouseSelectionsPassed) shiftClick=\(report.shiftMouseSelectionCount) selectAll=\(report.selectAllSelectionCount) shiftKey=\(report.shiftKeyboardSelectionCount) undo=\(report.undoDeletePassed) search=\(report.searchPassed) preview=\(report.previewPassed) doubleClick=\(report.doubleClickPastePassed)"
    )

default:
    fail("unknown display helper command: \(CommandLine.arguments[1])")
}
