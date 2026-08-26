import AppKit
import Foundation

enum AccessibilityPermissionSupport {
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    static func resetArguments(bundleIdentifier: String) -> [String] {
        ["reset", "Accessibility", bundleIdentifier]
    }

    /// Removes only cpsmart's stale Accessibility decision. macOS still requires the user to
    /// enable the refreshed entry in System Settings; applications cannot grant themselves access.
    static func resetCurrentApplication() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              !bundleIdentifier.isEmpty else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = resetArguments(bundleIdentifier: bundleIdentifier)
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
