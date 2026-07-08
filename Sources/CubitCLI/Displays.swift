import CoreGraphics

/// Active displays in CG-global canonical space (top-left origin, y-down, points), each with
/// its backing scale factor. Pure CoreGraphics — no AppKit, so no coordinate flipping.
enum Displays {
    struct Display {
        let id: CGDirectDisplayID
        let frame: CanonicalRect
        let scale: CGFloat
    }

    /// Ordered as `CGGetActiveDisplayList` returns them: the main display is first.
    static func all() -> [Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.map { id in
            let bounds = CGDisplayBounds(id)
            return Display(
                id: id,
                frame: CanonicalRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height),
                scale: scaleFactor(for: id)
            )
        }
    }

    /// Pixel-to-point ratio from the display's current mode (2.0 on a typical Retina panel).
    static func scaleFactor(for id: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return 1 }
        let points = mode.width
        return points > 0 ? CGFloat(mode.pixelWidth) / CGFloat(points) : 1
    }

    /// The display whose frame contains `point` (window's center), else the main display's
    /// scale as a sane fallback.
    static func scale(containing point: CanonicalPoint) -> CGFloat {
        for display in all() where contains(display.frame, point) { return display.scale }
        return scaleFactor(for: CGMainDisplayID())
    }

    private static func contains(_ rect: CanonicalRect, _ point: CanonicalPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
