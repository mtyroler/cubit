import Foundation

/// A handoff that arrived while the overlay was closed, waiting for the overlay to open.
///
/// A proposal is only queued when the app cannot present immediately — in practice, when the
/// Screen Recording onboarding gate stands between the agent's `cubit://show` and the overlay.
/// Two rules keep a queued proposal from surprising the user later:
///
/// 1. It EXPIRES. The overlay's next appearance may be minutes or hours later and triggered by the
///    user's hotkey, over entirely different content, with no agent involved. Injecting a stale
///    proposal there is indistinguishable from the app inventing measurements. A proposal is only
///    injected if the overlay opens within `maxAge` of the agent asking.
/// 2. It is DISCARDED when the user dismisses the gate (see `OverlayController.showOnboarding`).
///    Closing the permission window is a refusal, not a deferral.
struct PendingHandoff: Sendable {
    let measurements: [Measurement]
    let note: String?
    /// When the agent's handoff arrived.
    let queuedAt: Date

    /// How long a queued proposal stays injectable. Long enough to cover the permission dance
    /// (open System Settings, flip the toggle, come back); short enough that an abandoned proposal
    /// never reappears over unrelated content.
    static let maxAge: TimeInterval = 120

    /// True when the overlay is opening soon enough after the handoff for injection to still be
    /// what the user expects. A `now` before `queuedAt` (a backwards clock adjustment) is treated
    /// as stale rather than fresh — the conservative direction.
    func isFresh(now: Date, maxAge: TimeInterval = PendingHandoff.maxAge) -> Bool {
        let age = now.timeIntervalSince(queuedAt)
        return age >= 0 && age <= maxAge
    }
}
