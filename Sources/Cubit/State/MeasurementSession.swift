import Foundation
import Observation

@MainActor
@Observable
final class MeasurementSession {
    struct Draft: Equatable {
        var kind: MeasurementKind
        var anchor: CanonicalPoint
        var current: CanonicalPoint
        var constrain: Bool
        var fromCenter: Bool
    }

    var reference: CanonicalRect
    var referenceScale: CGFloat
    var tool: MeasurementKind = .rectangle
    var measurements: [Measurement] = []
    var draft: Draft?

    init(reference: CanonicalRect, scale: CGFloat) {
        self.reference = reference
        self.referenceScale = scale
    }

    var draftRect: CanonicalRect? {
        guard let draft else { return nil }
        return MeasurementEngine.draftRect(
            anchor: draft.anchor,
            current: draft.current,
            kind: draft.kind,
            constrain: draft.constrain,
            fromCenter: draft.fromCenter
        )
    }

    var currentPrimaryPercent: Double? {
        guard let draft, let rect = draftRect else { return nil }
        return MeasurementEngine.metrics(
            kind: draft.kind,
            rect: rect,
            reference: reference,
            scale: referenceScale
        ).primaryPercent
    }

    func beginDraft(at anchor: CanonicalPoint, constrain: Bool, fromCenter: Bool) {
        draft = Draft(kind: tool, anchor: anchor, current: anchor, constrain: constrain, fromCenter: fromCenter)
    }

    func updateDraft(to current: CanonicalPoint, constrain: Bool, fromCenter: Bool) {
        guard var draft else { return }
        draft.current = current
        draft.constrain = constrain
        draft.fromCenter = fromCenter
        self.draft = draft
    }

    @discardableResult
    func commitDraft(minDrag: CGFloat = 3) -> Measurement? {
        guard let draft, let rect = draftRect else { return nil }
        self.draft = nil

        let dx = draft.current.x - draft.anchor.x
        let dy = draft.current.y - draft.anchor.y
        guard (dx * dx + dy * dy).squareRoot() >= minDrag else { return nil }

        let measurement = Measurement(kind: draft.kind, rect: rect)
        measurements.append(measurement)
        return measurement
    }

    func cancelDraft() {
        draft = nil
    }

    func undo() {
        guard !measurements.isEmpty else { return }
        measurements.removeLast()
    }
}
