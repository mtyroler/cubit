import CoreGraphics
import Foundation

enum ReferenceFrameResolver {
    /// Windows smaller than this in either dimension (points) are ignored as reference targets.
    static let minWindowSize: CGFloat = 50

    static func resolve(
        mode: ReferenceMode,
        cursor: CanonicalPoint,
        screens: [CanonicalRect],
        customRect: CanonicalRect?,
        provider: WindowInfoProviding,
        excludedPID: pid_t
    ) -> ResolvedReference {
        switch mode {
        case .windowUnderCursor:
            if let window = topmostWindow(at: cursor, provider: provider, excludedPID: excludedPID) {
                return ResolvedReference(
                    rect: window.canonicalBounds,
                    mode: .windowUnderCursor,
                    descriptor: windowDescriptor(window),
                    window: window
                )
            }
            return screenReference(at: cursor, screens: screens)
        case .screen:
            return screenReference(at: cursor, screens: screens)
        case .custom:
            if let customRect {
                return ResolvedReference(
                    rect: customRect,
                    mode: .custom,
                    descriptor: descriptor(name: "Custom", rect: customRect)
                )
            }
            return screenReference(at: cursor, screens: screens)
        }
    }

    static func topmostWindow(
        at cursor: CanonicalPoint,
        provider: WindowInfoProviding,
        excludedPID: pid_t
    ) -> WindowInfo? {
        for window in provider.windows() {
            guard window.windowLayer == 0 else { continue }
            guard window.ownerPID != excludedPID else { continue }
            let bounds = window.canonicalBounds
            guard bounds.width >= minWindowSize, bounds.height >= minWindowSize else { continue }
            guard contains(bounds, cursor) else { continue }
            return window
        }
        return nil
    }

    private static func screenReference(at cursor: CanonicalPoint, screens: [CanonicalRect]) -> ResolvedReference {
        let rect = screens.first { contains($0, cursor) }
            ?? screens.first
            ?? CanonicalRect(x: 0, y: 0, width: 0, height: 0)
        return ResolvedReference(rect: rect, mode: .screen, descriptor: descriptor(name: "Screen", rect: rect))
    }

    private static func contains(_ rect: CanonicalRect, _ point: CanonicalPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    private static func windowDescriptor(_ window: WindowInfo) -> String {
        // Use the owning app's name (stable regardless of Screen Recording / TCC state)
        // rather than the per-window title, which leaks document names and is often nil.
        let name = window.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = name.isEmpty ? "Window" : name
        return descriptor(name: resolvedName, rect: window.canonicalBounds)
    }

    private static func descriptor(name: String, rect: CanonicalRect) -> String {
        "\(name) — \(Int(rect.width.rounded()))×\(Int(rect.height.rounded()))"
    }
}
