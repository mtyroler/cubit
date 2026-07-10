import AppKit

/// Speaks transient overlay feedback that has no lasting element to focus: the "Saved to …"
/// toast, the tool-switch flash, a handoff arriving. These are the moments a sighted user reads
/// off a pill that fades in three seconds; without an announcement they simply don't happen.
///
/// Announcements are posted against the app, not a view, so they're delivered even though the
/// overlay lives in a non-activating panel.
@MainActor
enum AccessibilityAnnouncer {
    /// `.high` interrupts whatever VoiceOver is saying — right for a confirmation the user just
    /// asked for (an export landing), wrong for incidental state. Default is `.medium`, which
    /// queues politely behind the current utterance.
    static func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .medium) {
        guard !message.isEmpty, NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.rawValue
            ]
        )
    }
}
