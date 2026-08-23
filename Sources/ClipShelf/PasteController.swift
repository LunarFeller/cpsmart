import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class PasteController {
    func paste(to targetApplication: NSRunningApplication?) -> Bool {
        guard requestAccessibilityAccessIfNeeded() else { return false }
        guard let targetApplication,
              targetApplication.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return false
        }

        targetApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        postPasteWhenApplicationIsActive(targetApplication, remainingAttempts: 5)
        return true
    }

    private func requestAccessibilityAccessIfNeeded() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func postPasteWhenApplicationIsActive(
        _ application: NSRunningApplication,
        remainingAttempts: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self else { return }
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if frontmostPID == application.processIdentifier {
                self.postCommandV()
            } else if remainingAttempts > 0 {
                application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                self.postPasteWhenApplicationIsActive(
                    application,
                    remainingAttempts: remainingAttempts - 1
                )
            }
        }
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: false
              ) else {
            return
        }

        keyDown.flags = [.maskCommand]
        keyUp.flags = [.maskCommand]
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
