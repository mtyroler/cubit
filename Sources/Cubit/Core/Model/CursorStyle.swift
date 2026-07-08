/// The four pointer states the overlay can be in — one per drawing tool plus the
/// transient custom-reference draw state. Pure enum so the badge symbol / flash
/// label mapping is testable without AppKit; the actual NSCursor image lives at
/// the UI edge (Overlay/ToolCursorFactory.swift).
enum CursorStyle: Equatable, Hashable, Sendable, CaseIterable {
    case rectangle
    case horizontal
    case vertical
    case customFrame
}

enum CursorStyleCatalog {
    static func style(forTool kind: MeasurementKind) -> CursorStyle {
        switch kind {
        case .rectangle: return .rectangle
        case .horizontal: return .horizontal
        case .vertical: return .vertical
        }
    }

    static func badgeSymbolName(for style: CursorStyle) -> String {
        switch style {
        case .rectangle: return "rectangle"
        case .horizontal: return "arrow.left.and.right"
        case .vertical: return "arrow.up.and.down"
        case .customFrame: return "rectangle.dashed"
        }
    }

    static func flashLabel(for style: CursorStyle) -> String {
        switch style {
        case .rectangle: return "Rectangle"
        case .horizontal: return "Horizontal line"
        case .vertical: return "Vertical line"
        case .customFrame: return "Custom frame"
        }
    }
}
