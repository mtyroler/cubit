import CoreGraphics

enum ReferenceMode: Equatable, Hashable, Sendable, CaseIterable {
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

    init(rect: CanonicalRect, mode: ReferenceMode, descriptor: String) {
        self.rect = rect
        self.mode = mode
        self.descriptor = descriptor
    }
}
