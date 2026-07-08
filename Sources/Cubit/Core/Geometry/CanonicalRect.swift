import CoreGraphics

struct CanonicalPoint: Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

struct CanonicalRect: Equatable, Sendable {
    var origin: CanonicalPoint
    var width: CGFloat
    var height: CGFloat

    init(origin: CanonicalPoint, width: CGFloat, height: CGFloat) {
        self.origin = origin
        self.width = width
        self.height = height
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(origin: CanonicalPoint(x: x, y: y), width: width, height: height)
    }

    var minX: CGFloat { origin.x }
    var minY: CGFloat { origin.y }
    var maxX: CGFloat { origin.x + width }
    var maxY: CGFloat { origin.y + height }

    var area: CGFloat { width * height }
}
