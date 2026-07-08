import Foundation

struct Measurement: Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: MeasurementKind
    var rect: CanonicalRect
    var label: String

    init(id: UUID = UUID(), kind: MeasurementKind, rect: CanonicalRect, label: String = "") {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.label = label
    }
}
