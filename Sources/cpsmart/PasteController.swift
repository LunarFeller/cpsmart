import AppKit
import Carbon.HIToolbox

enum PasteStartResult {
    case started
    case permissionRequired
    case targetUnavailable
}

final class PasteController {
    func paste(to targetApplication: NSRunningApplication?) -> PasteStartResult {
        guard let targetApplication,
              !targetApplication.isTerminated,
              targetApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return .targetUnavailable
        }

        guard CGPreflightPostEventAccess() else {
            _ = CGRequestPostEventAccess()
            return .permissionRequired
        }

        guard targetApplication.activate(
            options: [.activateAllWindows, .activateIgnoringOtherApps]
        ) else {
            return .targetUnavailable
        }
        postPasteWhenApplicationIsActive(targetApplication, remainingAttempts: 12)
        return .started
    }

    private func postPasteWhenApplicationIsActive(
        _ application: NSRunningApplication,
        remainingAttempts: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self else { return }
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if frontmostPID == application.processIdentifier || remainingAttempts == 0 {
                self.postCommandV(to: application.processIdentifier)
            } else if remainingAttempts > 0 {
                application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                self.postPasteWhenApplicationIsActive(
                    application,
                    remainingAttempts: remainingAttempts - 1
                )
            }
        }
    }

    private func postCommandV(to processID: pid_t) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
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
        keyDown.postToPid(processID)
        keyUp.postToPid(processID)
    }
}
