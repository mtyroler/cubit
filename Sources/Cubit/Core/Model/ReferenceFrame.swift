import CoreGraphics

enum ReferenceMode: String, Equatable, Hashable, Sendable, CaseIterable {
    case windowUnderCursor
    case screen
    case custom

    var next: ReferenceMode {
        switch self {
        case .windowUnderCursor: return .screen
        case .screen: return .custom
        case .custom: return .windowUnderCursor
        }
    }
}

struct ResolvedReference: Equatable, Sendable {
    var rect: CanonicalRect
    var mode: ReferenceMode
    var descriptor: String
    /// The resolved window, present only when `mode == .windowUnderCursor`. Carries owner
    /// PID/name/title so M6b metadata collection can identify the window and its app
    /// without re-querying the window server.
    var window: WindowInfo?

    init(rect: CanonicalRect, mode: ReferenceMode, descriptor: String, window: WindowInfo? = nil) {
        self.rect = rect
        self.mode = mode
        self.descriptor = descriptor
        self.window = window
    }
}
