import CoreGraphics

struct DisplayDescriptor: Equatable, Sendable {
    var id: UInt32
    var cocoaFrame: CGRect
    var scale: CGFloat

    init(id: UInt32, cocoaFrame: CGRect, scale: CGFloat) {
        self.id = id
        self.cocoaFrame = cocoaFrame
        self.scale = scale
    }
}

struct CoordinateConverter: Sendable {
    let primaryScreenHeight: CGFloat
    let displays: [DisplayDescriptor]

    init(primaryScreenHeight: CGFloat, displays: [DisplayDescriptor]) {
        self.primaryScreenHeight = primaryScreenHeight
        self.displays = displays
    }

    func canonical(fromCocoa point: CGPoint) -> CanonicalPoint {
        CanonicalPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    func cocoa(fromCanonical point: CanonicalPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    func canonical(fromCocoa rect: CGRect) -> CanonicalRect {
        CanonicalRect(
            x: rect.origin.x,
            y: primaryScreenHeight - (rect.origin.y + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    func cocoa(fromCanonical rect: CanonicalRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - (rect.origin.y + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    func canonicalFrame(of display: DisplayDescriptor) -> CanonicalRect {
        canonical(fromCocoa: display.cocoaFrame)
    }

    func displayLocal(_ point: CanonicalPoint, on display: DisplayDescriptor) -> CanonicalPoint {
        let frame = canonicalFrame(of: display)
        return CanonicalPoint(x: point.x - frame.origin.x, y: point.y - frame.origin.y)
    }

    func displayLocal(_ rect: CanonicalRect, on display: DisplayDescriptor) -> CanonicalRect {
        let localOrigin = displayLocal(rect.origin, on: display)
        return CanonicalRect(origin: localOrigin, width: rect.width, height: rect.height)
    }

    func pixels(points: CGFloat, on display: DisplayDescriptor) -> CGFloat {
        points * display.scale
    }

    func displayPixelRect(fromCanonical rect: CanonicalRect, on display: DisplayDescriptor) -> CGRect {
        let local = displayLocal(rect, on: display)
        return CGRect(
            x: local.origin.x * display.scale,
            y: local.origin.y * display.scale,
            width: local.width * display.scale,
            height: local.height * display.scale
        )
    }
}
