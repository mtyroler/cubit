import CoreGraphics
import Foundation

/// The live-overlay handoff document (v0.3 M4). An agent (via the `cubit` CLI or `cubit-mcp`
/// server) proposes measurements that light up as EDITABLE shapes on the user's real screen in
/// Cubit's overlay, where the human adjusts them with the existing handles and exports.
///
/// Coordinates are CANONICAL POINTS — top-left origin, y-down, points — the SAME space
/// `list_windows` / `measure_region` report. This is deliberate: the agent already gets canonical
/// frames from those tools, so it proposes measurements in canonical points and the app places
/// them 1:1 on the live overlay with NO image-pixel remapping. (Contrast the `cubit annotate`
/// regions schema, which is IMAGE PIXELS — a different, pixel-space type.)
///
/// This is its own versioned, canonical-space type; it does not overload the pixel-space
/// `RegionsInput`. Shape:
/// ```json
/// {
///   "schemaVersion": 1,
///   "note": "Proposed layout for the sidebar",
///   "measurements": [
///     { "kind": "rectangle", "rect": { "x": 320, "y": 140, "width": 480, "height": 300 },
///       "label": "hero", "colorIndex": 0 },
///     { "kind": "horizontal", "endpoints": [ { "x": 320, "y": 480 }, { "x": 800, "y": 480 } ] },
///     { "kind": "vertical",   "endpoints": [ { "x": 320, "y": 140 }, { "x": 320, "y": 440 } ] }
///   ]
/// }
/// ```
/// `schemaVersion` defaults to the current version when omitted; a rectangle needs a `rect`; a
/// line needs two `endpoints`. `note`, `label`, and `colorIndex` are optional.
struct HandoffDocument: Codable, Sendable, Equatable {
    /// The schema this document targets. Only `HandoffDocument.currentSchemaVersion` is accepted;
    /// an explicit unknown version is rejected by `HandoffMapper`. Defaults to the current version
    /// when the JSON omits it, so a hand-authored document need not spell it out.
    var schemaVersion: Int
    /// Optional freeform note surfaced in the overlay's arrival affordance.
    var note: String?
    var measurements: [ProposedMeasurement]

    static let currentSchemaVersion = 1

    struct Point: Codable, Sendable, Equatable {
        var x: Double
        var y: Double
    }

    struct Rect: Codable, Sendable, Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// One proposed measurement. `kind == rectangle` uses `rect`; `kind == horizontal|vertical`
    /// uses two `endpoints`. All coordinates are canonical points.
    struct ProposedMeasurement: Codable, Sendable, Equatable {
        var kind: String
        var rect: Rect?
        var endpoints: [Point]?
        var label: String?
        var colorIndex: Int?
    }

    init(schemaVersion: Int = HandoffDocument.currentSchemaVersion, note: String? = nil, measurements: [ProposedMeasurement]) {
        self.schemaVersion = schemaVersion
        self.note = note
        self.measurements = measurements
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, note, measurements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // An omitted schemaVersion means "current" — a convenience for hand-authored documents.
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? HandoffDocument.currentSchemaVersion
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
        self.measurements = try container.decode([ProposedMeasurement].self, forKey: .measurements)
    }
}
