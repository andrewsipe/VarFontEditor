import AppKit

enum SaveReviewWindowLifecycle {
    static let identifier = "save-review"

    /// Close Save Review windows restored by macOS from a prior session.
    static func closeRestoredWindows() {
        for window in NSApplication.shared.windows where isSaveReviewWindow(window) {
            window.isRestorable = false
            window.close()
        }
    }

    /// macOS may restore auxiliary windows after `applicationDidFinishLaunching`; retry briefly.
    static func scheduleCloseRestoredWindows() {
        closeRestoredWindows()
        for delay in [0.05, 0.2, 0.5, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                closeRestoredWindows()
            }
        }
    }

    static func isSaveReviewWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue == identifier {
            return true
        }
        return window.title.lowercased().hasPrefix("review")
            || window.title.lowercased().hasPrefix("save review")
    }
}
