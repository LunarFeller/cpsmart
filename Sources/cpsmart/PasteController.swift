import AppKit
import Carbon.HIToolbox

enum PasteStartResult {
    case started
    case permissionRequired
    case targetUnavailable
}

final class PasteController {
    func paste(
        to targetApplication: NSRunningApplication?,
        onPastePosted: (() -> Void)? = nil
    ) -> PasteStartResult {
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
        postPasteWhenApplicationIsActive(
            targetApplication,
            remainingAttempts: 12,
            onPastePosted: onPastePosted
        )
        return .started
    }

    private func postPasteWhenApplicationIsActive(
        _ application: NSRunningApplication,
        remainingAttempts: Int,
        onPastePosted: (() -> Void)?
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self else { return }
            guard !application.isTerminated else { return }
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if frontmostPID == application.processIdentifier || remainingAttempts == 0 {
                if self.postCommandV(to: application.processIdentifier) {
                    onPastePosted?()
                }
            } else if remainingAttempts > 0 {
                application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                self.postPasteWhenApplicationIsActive(
                    application,
                    remainingAttempts: remainingAttempts - 1,
                    onPastePosted: onPastePosted
                )
            }
        }
    }

    private func postCommandV(to processID: pid_t) -> Bool {
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
            return false
        }

        keyDown.flags = [.maskCommand]
        keyUp.flags = [.maskCommand]
        keyDown.postToPid(processID)
        keyUp.postToPid(processID)
        return true
    }
}
