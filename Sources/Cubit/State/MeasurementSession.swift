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

    // MARK: Undo

    /// The session's document state, as undo sees it. The custom reference and mode ride along
    /// with the measurements: drawing a custom frame is an edit, and undo has to unwind it too.
    private struct Snapshot {
        var measurements: [Measurement]
        var selectedID: UUID?
        var customRect: CanonicalRect?
        var mode: ReferenceMode
    }

    /// Real `UndoManager`, not a snapshot array: redo, action names, and unbounded depth come
    /// free, and the menu/tool-pill affordances can read `undoActionName` to title themselves.
    /// `groupsByEvent` is off so each registration is exactly one step — deterministic, and
    /// testable without pumping a run loop.
    let undoManager: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }()

    /// `UndoManager` predates observation, so its state is mirrored here for the SwiftUI
    /// tool pill. Kept in sync by `syncUndoState()` after every mutation, undo, and redo.
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoActionName = ""
    private(set) var redoActionName = ""

    /// Distinct streaks of the same continuous edit on the same measurement collapse into the
    /// one undo step that preceded them. Holding an arrow key fires a `keyDown` per repeat;
    /// without this, sixty of them would bury the step that created the shape.
    private enum CoalesceKey: Equatable {
        case color(UUID)
        case geometry(UUID)
    }

    private static let coalesceWindow: TimeInterval = 1.0
    private var lastCoalesceKey: CoalesceKey?
    private var lastCoalesceAt: Date?

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

        registerUndo("Add Measurement")
        let measurement = Measurement(kind: kind, rect: finalRect, colorIndex: draft.colorIndex)
        measurements.append(measurement)
        selectedID = measurement.id
        return measurement
    }

    func cancelDraft() {
        draft = nil
    }

    /// Injects agent-proposed measurements (a live-overlay handoff) as first-class editable
    /// measurements. The whole proposal collapses into ONE undo step so the user can undo the
    /// entire handoff, and the first injected measurement becomes selected so the existing
    /// selection handles are immediately live on it. Returns false for an empty proposal.
    @discardableResult
    func injectProposed(_ proposed: [Measurement]) -> Bool {
        guard !proposed.isEmpty else { return false }
        registerUndo(proposed.count == 1 ? "Insert Proposed Measurement" : "Insert Proposed Measurements")
        measurements.append(contentsOf: proposed)
        selectedID = proposed.first?.id
        return true
    }

    /// Re-seeds a fresh session with the measurements a previous one was carrying (see
    /// `OverlayController`'s restore path). Undoable as a single step so ⌘Z means "no, I did
    /// want the clean slate".
    @discardableResult
    func restore(_ restored: [Measurement], customRect: CanonicalRect?, mode: ReferenceMode) -> Bool {
        guard !restored.isEmpty else { return false }
        registerUndo("Restore Measurements")
        measurements = restored
        self.customRect = customRect
        self.mode = mode
        selectedID = nil
        return true
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
        registerUndo("Set Custom Reference")
        customRect = rect
        mode = .custom
        return true
    }

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        endCoalescing()
        syncUndoState()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        endCoalescing()
        syncUndoState()
    }

    // MARK: Undo plumbing

    private func currentSnapshot() -> Snapshot {
        Snapshot(measurements: measurements, selectedID: selectedID, customRect: customRect, mode: mode)
    }

    private func apply(_ snapshot: Snapshot) {
        measurements = snapshot.measurements
        customRect = snapshot.customRect
        mode = snapshot.mode
        selectedID = snapshot.selectedID.flatMap { id in
            measurements.contains(where: { $0.id == id }) ? id : nil
        }
    }

    /// Registers the pre-edit state as one undo step. Call BEFORE mutating.
    ///
    /// `coalescing` collapses a rapid streak of the same edit on the same measurement (holding
    /// an arrow key, tapping through digits) into the step that preceded the streak. A `nil`
    /// key ends any streak in progress, so the next edit always registers.
    private func registerUndo(_ actionName: String, coalescing key: CoalesceKey? = nil) {
        if let key, key == lastCoalesceKey, let last = lastCoalesceAt,
           Date().timeIntervalSince(last) < Self.coalesceWindow {
            lastCoalesceAt = Date()
            return
        }
        lastCoalesceKey = key
        lastCoalesceAt = key == nil ? nil : Date()
        registerSnapshot(actionName)
    }

    /// Symmetric registration: undoing re-registers the state it is about to replace, which is
    /// what makes the step redoable. `UndoManager` routes that registration onto the redo stack
    /// automatically while an undo is in flight.
    private func registerSnapshot(_ actionName: String) {
        let snapshot = currentSnapshot()
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated {
                session.registerSnapshot(actionName)
                session.apply(snapshot)
                session.syncUndoState()
            }
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
        syncUndoState()
    }

    private func endCoalescing() {
        lastCoalesceKey = nil
        lastCoalesceAt = nil
    }

    private func syncUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
        undoActionName = undoManager.undoActionName
        redoActionName = undoManager.redoActionName
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
        registerUndo("Change Color", coalescing: .color(selectedID))
        measurements[index].colorIndex = Palette.cycledIndex(measurements[index].colorIndex, forward: forward)
    }

    private func setSelectedColor(index newIndex: Int) {
        guard let selectedID, let index = measurements.firstIndex(where: { $0.id == selectedID }) else { return }
        registerUndo("Change Color", coalescing: .color(selectedID))
        measurements[index].colorIndex = newIndex
    }

    // MARK: Selection & editing

    var selectedMeasurement: Measurement? {
        guard let selectedID else { return nil }
        return measurements.first { $0.id == selectedID }
    }

    func select(_ id: UUID?) {
        selectedID = id
    }

    /// Call once at the start of an interactive drag so the whole gesture collapses into a
    /// single undo step. The drag's own mutations (`updateSelectedRect`) register nothing.
    func beginTransientEdit(actionName: String = "Move Measurement") {
        registerUndo(actionName)
    }

    func updateSelectedRect(_ rect: CanonicalRect) {
        guard let selectedID, let index = measurements.firstIndex(where: { $0.id == selectedID }) else { return }
        measurements[index].rect = rect
    }

    /// Arrow-key move. Auto-repeat fires this many times a second, so the streak coalesces —
    /// one held keypress is one undo step, not sixty that evict the step you actually wanted.
    func nudgeSelected(dx: CGFloat, dy: CGFloat) {
        guard let selectedID, let index = measurements.firstIndex(where: { $0.id == selectedID }) else { return }
        registerUndo("Move Measurement", coalescing: .geometry(selectedID))
        measurements[index].rect = MeasurementEngine.moved(measurements[index].rect, dx: dx, dy: dy)
    }

    /// Arrow-key resize. Coalesces on the same key as `nudgeSelected` on purpose: a streak of
    /// move-then-resize on one measurement is a single continuous adjustment to the user.
    func resizeSelected(edge: RectEdge, by delta: CGFloat) {
        guard let selectedID, let index = measurements.firstIndex(where: { $0.id == selectedID }) else { return }
        registerUndo("Resize Measurement", coalescing: .geometry(selectedID))
        measurements[index].rect = MeasurementEngine.resized(measurements[index].rect, edge: edge, by: delta)
    }

    func deleteSelected() {
        guard let selectedID, let index = measurements.firstIndex(where: { $0.id == selectedID }) else { return }
        registerUndo("Delete Measurement")
        measurements.remove(at: index)
        self.selectedID = nil
    }

    /// Copies the selected measurement, offset down-right so it reads as a new shape rather
    /// than a redraw. The duplicate takes the next unused palette color and becomes selected.
    @discardableResult
    func duplicateSelected(offset: CGFloat = 12) -> Measurement? {
        guard let selected = selectedMeasurement else { return nil }
        registerUndo("Duplicate Measurement")
        let copy = Measurement(
            kind: selected.kind,
            rect: MeasurementEngine.moved(selected.rect, dx: offset, dy: offset),
            label: selected.label,
            colorIndex: nextColorIndex()
        )
        measurements.append(copy)
        selectedID = copy.id
        return copy
    }

    @discardableResult
    func clearAll() -> Bool {
        guard !measurements.isEmpty else { return false }
        registerUndo("Clear All Measurements")
        measurements.removeAll()
        selectedID = nil
        return true
    }

    func setLabel(_ label: String, for id: UUID) {
        guard let index = measurements.firstIndex(where: { $0.id == id }) else { return }
        guard measurements[index].label != label else { return }
        registerUndo(label.isEmpty ? "Remove Label" : "Rename Measurement")
        measurements[index].label = label
    }
}
