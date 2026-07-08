import AppKit

/// Builds the per-tool overlay cursors: a crosshair (dark outline + white core so it
/// reads on any background) with a small badge glyph at the lower-right of the
/// hotspot. Generated at runtime — no asset files, SF Symbols only. Cursors are
/// cached per style since NSCursor/NSImage construction isn't free and the same
/// four styles repeat for the life of the overlay.
@MainActor
enum ToolCursorFactory {
    static let canvasSize = CGSize(width: 32, height: 32)
    private static let hotspot = CGPoint(x: 16, y: 16)

    private static var cursorCache: [CursorStyle: NSCursor] = [:]

    static func cursor(for style: CursorStyle) -> NSCursor {
        if let cached = cursorCache[style] { return cached }
        let cursor = NSCursor(image: image(for: style), hotSpot: hotspot)
        cursorCache[style] = cursor
        return cursor
    }

    /// Exposed separately from `cursor(for:)` for visual verification (rendering to
    /// PNG) — NSCursor doesn't expose its backing image for inspection.
    static func image(for style: CursorStyle) -> NSImage {
        NSImage(size: canvasSize, flipped: false) { rect in
            drawCrosshair(in: rect)
            drawBadge(symbolName: CursorStyleCatalog.badgeSymbolName(for: style), in: rect)
            return true
        }
    }

    private static func drawCrosshair(in rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let armLength: CGFloat = 7
        let gap: CGFloat = 3

        func arms() -> NSBezierPath {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: center.x - armLength, y: center.y))
            path.line(to: CGPoint(x: center.x - gap, y: center.y))
            path.move(to: CGPoint(x: center.x + gap, y: center.y))
            path.line(to: CGPoint(x: center.x + armLength, y: center.y))
            path.move(to: CGPoint(x: center.x, y: center.y - armLength))
            path.line(to: CGPoint(x: center.x, y: center.y - gap))
            path.move(to: CGPoint(x: center.x, y: center.y + gap))
            path.line(to: CGPoint(x: center.x, y: center.y + armLength))
            path.lineCapStyle = .round
            return path
        }

        // Dark outline pass first (wider), then a white core (narrower) on top, so
        // the crosshair stays legible over both light and dark backgrounds.
        let outline = arms()
        outline.lineWidth = 3
        NSColor.black.withAlphaComponent(0.85).setStroke()
        outline.stroke()

        let core = arms()
        core.lineWidth = 1.25
        NSColor.white.setStroke()
        core.stroke()
    }

    private static func drawBadge(symbolName: String, in rect: CGRect) {
        let center = CGPoint(x: rect.midX + 8, y: rect.midY - 8)
        let radius: CGFloat = 7.5

        let backdrop = NSBezierPath(ovalIn: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
        ))
        NSColor.black.withAlphaComponent(0.8).setFill()
        backdrop.fill()

        guard
            let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        else { return }

        let whiteSymbol = tinted(symbol, color: .white)
        let size = whiteSymbol.size
        whiteSymbol.draw(
            in: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    /// SF Symbol images render in their default fill; overwrite the drawn (non-transparent)
    /// pixels with a solid color while preserving the glyph's alpha shape.
    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let output = NSImage(size: image.size)
        output.lockFocus()
        let imageRect = CGRect(origin: .zero, size: image.size)
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        imageRect.fill(using: .sourceAtop)
        output.unlockFocus()
        return output
    }
}
