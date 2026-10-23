import ApplicationServices

enum AccessibilityAccess {
    /// Checking permission must never trigger the system authorization dialog.
    /// A stale grant must be replaced in Settings, not repeatedly requested.
    static var isGranted: Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ] as CFDictionary)
    }
}
