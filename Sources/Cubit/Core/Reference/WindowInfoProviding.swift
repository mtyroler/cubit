import Foundation

struct WindowInfo: Equatable, Sendable {
    var canonicalBounds: CanonicalRect
    var ownerName: String
    var windowLayer: Int
    var ownerPID: pid_t
    var windowID: UInt32
    var title: String?

    init(
        canonicalBounds: CanonicalRect,
        ownerName: String,
        windowLayer: Int,
        ownerPID: pid_t,
        windowID: UInt32,
        title: String? = nil
    ) {
        self.canonicalBounds = canonicalBounds
        self.ownerName = ownerName
        self.windowLayer = windowLayer
        self.ownerPID = ownerPID
        self.windowID = windowID
        self.title = title
    }
}

protocol WindowInfoProviding: Sendable {
    /// On-screen windows ordered front-to-back.
    func windows() -> [WindowInfo]
}
