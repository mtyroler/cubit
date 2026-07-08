import CoreGraphics

/// Pure mapping from a captured display image (pixels) to the region of an overlay canvas
/// (points) that should show the frozen snapshot. The mapping is always 1:1 — destination
/// points times scale equal source pixels — so the snapshot can never be vertically squashed,
/// even if the canvas ends up shorter than the display. The top menu-bar strip is excluded so
/// the live, always-on-top menu bar isn't ghosted by a frozen copy beneath it.
enum FrozenBackgroundLayout {
    struct Layout: Equatable {
        /// Region of the CGImage to draw, in image pixels (origin top-left).
        var sourcePixelRect: CGRect
        /// Region of the canvas to draw into, in points (origin top-left / flipped view).
        var destPointRect: CGRect

        var isEmpty: Bool { destPointRect.height <= 0 || destPointRect.width <= 0 }
    }

    static func layout(
        imagePixelWidth: CGFloat,
        imagePixelHeight: CGFloat,
        scale: CGFloat,
        canvasSize: CGSize,
        topInsetPoints: CGFloat
    ) -> Layout {
        let safeScale = max(scale, 0.0001)
        let displayPointWidth = imagePixelWidth / safeScale
        let displayPointHeight = imagePixelHeight / safeScale

        // The canvas is anchored at the display's top-left, so it shows at most the display's
        // extent; a constrained (shorter) canvas simply shows less, never a rescaled image.
        let top = max(0, topInsetPoints)
        let destWidth = min(canvasSize.width, displayPointWidth)
        let destBottom = min(canvasSize.height, displayPointHeight)
        let destRect = CGRect(
            x: 0,
            y: top,
            width: max(0, destWidth),
            height: max(0, destBottom - top)
        )

        let sourceRect = CGRect(
            x: destRect.minX * safeScale,
            y: destRect.minY * safeScale,
            width: destRect.width * safeScale,
            height: destRect.height * safeScale
        )
        return Layout(sourcePixelRect: sourceRect, destPointRect: destRect)
    }
}
