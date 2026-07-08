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

    struct CustomDraft: Equatable {
        var anchor: CanonicalPoint
        var current: CanonicalPoint
    }

    var referenceScale: CGFloat
    var mode: ReferenceMode
    var resolved: ResolvedReference
    var customRect: CanonicalRect?
    var isDrawingCustom = false
    var customDraft: CustomDraft?

    var tool: MeasurementKind = .rectangle
    var measurements: [Measurement] = []
    var draft: Draft?
    var selectedID: UUID?

    private let fallbackRect: CanonicalRect
    private var undoStack: [[Measurement]] = []

    init(screenReference: CanonicalRect, scale: CGFloat, mode: ReferenceMode = .windowUnderCursor) {
        self.fallbackRect = screenReference
        self.referenceScale = scale
        self.mode = mode
        self.resolved = ResolvedReference(
            rect: screenReference,
            mode: .screen,
            descriptor: "Screen — \(Int(screenReference.width.rounded()))×\(Int(screenReference.height.rounded()))"
        )
    }

    var reference: CanonicalRect { resolved.rect }

    /// Recompute the active reference against the current cursor and mode.
    func resolveReference(
        cursor: CanonicalPoint,
        screens: [CanonicalRect],
        provider: WindowInfoProviding,
        excludedPID: pid_t
    ) {
        resolved = ReferenceFrameResolver.resolve(
            mode: mode,
            cursor: cursor,
            screens: screens.isEmpty ? [fallbackRect] : screens,
            customRect: customRect,
            provider: provider,
            excludedPID: excludedPID
        )
    }

    func cycleMode() {
        mode = mode.next
        isDrawingCustom = false
        customDraft = nil
    }

    func beginCustomDraw() {
        isDrawingCustom = true
        customDraft = nil
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

    var customDraftRect: CanonicalRect? {
        guard let customDraft else { return nil }
        return MeasurementEngine.draftRect(
            anchor: customDraft.anchor,
            current: customDraft.current,
            kind: .rectangle,
            constrain: false,
            fromCenter: false
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

        pushUndo()
        let measurement = Measurement(kind: draft.kind, rect: rect, colorIndex: nextColorIndex())
        measurements.append(measurement)
        selectedID = measurement.id
        return measurement
    }

    func cancelDraft() {
        draft = nil
    }

    // MARK: Custom reference drawing

    func beginCustomDraft(at anchor: CanonicalPoint) {
        customDraft = CustomDraft(anchor: anchor, current: anchor)
    }

    func updateCustomDraft(to current: CanonicalPoint) {
        guard var customDraft else { return }
        customDraft.current = current
        self.customDraft = customDraft
    }

    /// Finish a custom-reference drag. Adopts the drawn rect when it is large enough
    /// and switches to `.custom` mode; a too-small drag is discarded.
    @discardableResult
    func commitCustomDraft(minDrag: CGFloat = 3) -> Bool {
        defer { isDrawingCustom = false; customDraft = nil }
        guard let customDraft, let rect = customDraftRect else { return false }
        let dx = customDraft.current.x - customDraft.anchor.x
        let dy = customDraft.current.y - customDraft.anchor.y
        guard (dx * dx + dy * dy).squareRoot() >= minDrag else { return false }
        customRect = rect
        mode = .custom
        return true
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        measurements = previous
        if let selectedID, !measurements.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    // MARK: Color assignment

    private func nextColorIndex() -> Int {
        let used = Set(measurements.map(\.colorIndex))
        var index = 0
        while used.contains(index) { index += 1 }
        return index
    }

    // MARK: Selection & editing

    var selectedMeasurement: Measurement? {
        guard let selectedID else { return nil }
        return measurements.first { $0.id == selectedID }
    }

    func select(_ id: UUID?) {
        selectedID = id
    }

    /// Call once at the start of an interactive drag/nudge sequence so the whole
    /// gesture collapses into a single undo step.
    func beginTransientEdit() {
        pushUndo()
    }

    func updateSelectedRect(_ rect: CanonicalRect) {
        guard let selectedID, let index = measurements.firstIndex(where: { $0.id == selectedID }) else { return }
        measurements[index].rect = rect
    }

    func nudgeSelected(dx: CGFloat, dy: CGFloat) {
        guard let selectedID, let index = measurements.firstIndex(where: { $0.id == selectedID }) else { return }
        pushUndo()
        measurements[index].rect = MeasurementEngine.moved(measurements[index].rect, dx: dx, dy: dy)
    }

    func resizeSelected(edge: RectEdge, by delta: CGFloat) {
        guard let selectedID, let index = measurements.firstIndex(where: { $0.id == selectedID }) else { return }
        pushUndo()
        measurements[index].rect = MeasurementEngine.resized(measurements[index].rect, edge: edge, by: delta)
    }

    func deleteSelected() {
        guard let selectedID, let index = measurements.firstIndex(where: { $0.id == selectedID }) else { return }
        pushUndo()
        measurements.remove(at: index)
        self.selectedID = nil
    }

    func setLabel(_ label: String, for id: UUID) {
        guard let index = measurements.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        measurements[index].label = label
    }

    private func pushUndo() {
        undoStack.append(measurements)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }
}
