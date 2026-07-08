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
        var colorIndex: Int
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
        draft = Draft(kind: tool, anchor: anchor, current: anchor, constrain: constrain, fromCenter: fromCenter, colorIndex: nextColorIndex())
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

        let (kind, finalRect) = MeasurementEngine.classifyForCommit(kind: draft.kind, rect: rect)

        pushUndo()
        let measurement = Measurement(kind: kind, rect: finalRect, colorIndex: draft.colorIndex)
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

    /// Color of the active draft while drafting/dragging, else the selected measurement's
    /// color; nil when neither exists (nothing for X / 1–8 / the pill swatch to act on).
    var currentColorIndex: Int? {
        if let draft { return draft.colorIndex }
        if let selectedMeasurement { return selectedMeasurement.colorIndex }
        return nil
    }

    /// Cycles the color of the active draft, else the selected measurement. X / Shift+X.
    func cycleColor(forward: Bool) {
        if draft != nil {
            cycleDraftColor(forward: forward)
        } else {
            cycleSelectedColor(forward: forward)
        }
    }

    /// Jumps the color of the active draft, else the selected measurement, to a specific
    /// palette index. Digit keys 1–8 (mapped to index 0–7 by the caller).
    func setColor(index: Int) {
        guard Palette.colors.indices.contains(index) else { return }
        if draft != nil {
            setDraftColor(index: index)
        } else {
            setSelectedColor(index: index)
        }
    }

    private func cycleDraftColor(forward: Bool) {
        guard var draft else { return }
        draft.colorIndex = Palette.cycledIndex(draft.colorIndex, forward: forward)
        self.draft = draft
    }

    private func setDraftColor(index: Int) {
        guard var draft else { return }
        draft.colorIndex = index
        self.draft = draft
    }

    private func cycleSelectedColor(forward: Bool) {
        guard let selectedID, let index = measurements.firstIndex(where: { $0.id == selectedID }) else { return }
        beginColorEdit(for: selectedID)
        measurements[index].colorIndex = Palette.cycledIndex(measurements[index].colorIndex, forward: forward)
    }

    private func setSelectedColor(index newIndex: Int) {
        guard let selectedID, let index = measurements.firstIndex(where: { $0.id == selectedID }) else { return }
        beginColorEdit(for: selectedID)
        measurements[index].colorIndex = newIndex
    }

    /// Committed color edits participate in undo, but rapid cycling (holding X, or tapping
    /// through several digits) on the *same* measurement within this window collapses into
    /// the one undo step that preceded the streak, rather than one step per keystroke.
    private static let colorEditCoalesceWindow: TimeInterval = 1.0
    private var lastColorEditID: UUID?
    private var lastColorEditAt: Date?

    private func beginColorEdit(for id: UUID) {
        let now = Date()
        let coalescing = lastColorEditID == id
            && lastColorEditAt.map { now.timeIntervalSince($0) < Self.colorEditCoalesceWindow } == true
        if !coalescing { pushUndo() }
        lastColorEditID = id
        lastColorEditAt = now
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
