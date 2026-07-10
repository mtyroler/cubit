import CoreGraphics
import Foundation
import ImageIO

/// The four Cubit MCP tools. Each wraps the SAME logic the `cubit` CLI uses (window
/// enumeration, the geometry engine, the annotated-export renderer), so results are identical
/// across surfaces. Tool failures come back as `ToolResult(isError: true)` with a tagged prefix
/// (`invalid_arguments:`, `not_found:`, `permission_denied:`) so an agent can branch on them.
@MainActor
enum MCPTools {
    // MARK: - Tool catalog (names, descriptions, JSON Schemas)

    static let descriptors: [ToolDescriptor] = [
        ToolDescriptor(
            name: "list_windows",
            description: """
            List on-screen windows front-to-back with their owner app, title, canonical frame \
            (points, top-left origin, y-down), display scale, and window layer. Also reports \
            whether Screen Recording is granted — without it macOS hides window titles (frames \
            are still returned).
            """,
            inputSchema: schema(Schemas.listWindows)
        ),
        ToolDescriptor(
            name: "measure_region",
            description: """
            Measure a rectangle or line against a reference (a window, a display, or an explicit \
            rect) and return width/height/area percentages and sizes in points and pixels — no \
            screenshot or export required. Coordinates are canonical points (top-left origin, \
            y-down), the same space list_windows reports.
            """,
            inputSchema: schema(Schemas.measureRegion)
        ),
        ToolDescriptor(
            name: "annotate_screenshot",
            description: """
            Render Cubit-style measurement annotations onto an existing image (path or base64) \
            and return the annotated PNG plus the measurement JSON. Pixel-identical to the app \
            and CLI exports. Region coordinates are in IMAGE PIXELS. Writes to outputPath, or \
            returns the PNG inline as a base64 image block when outputPath is omitted.
            """,
            inputSchema: schema(Schemas.annotateScreenshot)
        ),
        ToolDescriptor(
            name: "show_overlay",
            description: """
            Propose measurements that light up as EDITABLE shapes on the user's REAL screen in \
            Cubit's overlay, where they drag/resize/relabel them and export. Coordinates are \
            canonical points (top-left origin, y-down), the same space list_windows reports — so \
            propose measurements straight from those frames with no remapping. Presents the \
            overlay (stealing focus) and is user-adjustable; it never captures or exports on its \
            own. Requires the Cubit app to be installed. Up to 200 measurements. IMPORTANT: a \
            successful result means the proposal was DELIVERED to the app, not that the user can \
            see it — Cubit shows a permission gate first if it lacks Screen Recording, and drops \
            the proposal if the user dismisses that gate. Do not tell the user measurements are on \
            their screen; ask them what they see.
            """,
            inputSchema: schema(Schemas.showOverlay)
        ),
        ToolDescriptor(
            name: "analyze_dead_space",
            description: """
            Compute how much of a window/display/rect is unused ("dead") space, given the \
            content rectangles you have already measured. Returns the reference area, the summed \
            used area, the used percentage, and the dead-space percentage (100 − used%), with a \
            per-region breakdown. Geometry only — it does NOT detect content; you supply the \
            content regions (canonical points).
            """,
            inputSchema: schema(Schemas.analyzeDeadSpace)
        ),
    ]

    // MARK: - Dispatch

    static func call(name: String, arguments: JSONValue?, context: ToolContext) -> ToolResult {
        do {
            switch name {
            case "list_windows": return try listWindows(arguments)
            case "measure_region": return try measureRegion(arguments)
            case "annotate_screenshot": return try annotateScreenshot(arguments, context: context)
            case "show_overlay": return try showOverlay(arguments)
            case "analyze_dead_space": return try analyzeDeadSpace(arguments)
            default: return .failure("unknown_tool: no tool named '\(name)'")
            }
        } catch {
            return mapError(error)
        }
    }

    /// Maps a thrown error to a tagged tool-failure result. The tag lets an agent branch:
    /// `permission_denied:` (grant Screen Recording), `forbidden:` (path outside the sandbox),
    /// `too_large:` (input over a limit), `not_found:`, or `invalid_arguments:`.
    static func mapError(_ error: Error) -> ToolResult {
        switch error {
        case let toolError as MCPToolError:
            switch toolError {
            case .forbidden(let message): return .failure("forbidden: " + message)
            case .tooLarge(let message): return .failure("too_large: " + message)
            }
        case let cliError as CLIError:
            let prefix: String
            switch cliError.code {
            case .permissionDenied: prefix = "permission_denied: "
            case .notFound: prefix = "not_found: "
            case .usage: prefix = "invalid_arguments: "
            case .generic, .ok: prefix = "error: "
            }
            return .failure(prefix + cliError.message)
        default:
            return .failure("error: \(error.localizedDescription)")
        }
    }

    // MARK: - list_windows

    struct ListWindowsArgs: Decodable {
        let onScreenOnly: Bool?
    }

    static func listWindows(_ arguments: JSONValue?) throws -> ToolResult {
        _ = try decodeArguments(arguments, as: ListWindowsArgs.self) // validates arg shape
        let document = WindowsCommand.buildDocument(
            windows: CGWindowInfoProvider().windows(),
            screenRecordingGranted: CGPreflightScreenCaptureAccess()
        )
        return .ok([.text(try prettyJSON(document))])
    }

    // MARK: - measure_region

    struct MeasureArgs: Decodable {
        let region: RegionsInput.Region
        let reference: ReferenceArg?
        let scale: Double?
    }

    static func measureRegion(_ arguments: JSONValue?) throws -> ToolResult {
        let args = try decodeArguments(arguments, as: MeasureArgs.self)
        try validate(args.region)
        if let rect = args.reference?.rect { try validate(rect) }
        // Canonical-space region: interpret input coordinates as points (scale 1 → no division).
        let measurement = try RegionsResolver.measurement(from: args.region, index: 0, scale: 1)
        let center = CanonicalPoint(
            x: measurement.rect.minX + measurement.rect.width / 2,
            y: measurement.rect.minY + measurement.rect.height / 2
        )
        let ref = try resolveReference(args.reference, regionCenter: center)
        let scale = resolveScale(explicit: args.scale, center: center)
        let metrics = MeasurementEngine.metrics(for: measurement, reference: ref.rect, scale: scale)

        let result = MeasureResult(
            kind: measurement.kind.rawValue,
            valueText: ExportRenderer.primaryText(metrics),
            detailText: ExportRenderer.detailText(kind: measurement.kind, metrics: metrics),
            sizePoints: MeasureResult.Size(width: Double(measurement.rect.width), height: Double(measurement.rect.height)),
            sizePixels: MeasureResult.Size(width: Double(metrics.widthPx), height: Double(metrics.heightPx)),
            percentages: MeasureResult.Percentages(
                width: metrics.widthPercent,
                height: metrics.heightPercent,
                area: metrics.areaPercent,
                primary: metrics.primaryPercent
            ),
            reference: MeasureResult.Reference(
                kind: ref.kind,
                name: ref.name,
                rectPoints: MeasureResult.Rect(rect: ref.rect),
                areaPoints: Double(ref.rect.area)
            ),
            scale: Double(scale)
        )
        return .ok([.text(try prettyJSON(result))])
    }

    // MARK: - annotate_screenshot

    struct AnnotateArgs: Decodable {
        let imagePath: String?
        let imageBase64: String?
        let regions: RegionsInput
        let outputPath: String?
        let sidecar: Bool?
        let totals: Bool?
        let scale: Double?
    }

    static func annotateScreenshot(_ arguments: JSONValue?, context: ToolContext) throws -> ToolResult {
        let args = try decodeArguments(arguments, as: AnnotateArgs.self)
        guard args.regions.regions.count <= MCPLimits.maxRegions else {
            throw MCPToolError.tooLarge("regions array has \(args.regions.regions.count) items; the limit is \(MCPLimits.maxRegions)")
        }
        for region in args.regions.regions { try validate(region) }
        if let rect = args.regions.reference?.rect { try validate(rect) }

        let image = try loadImage(path: args.imagePath, base64: args.imageBase64, sandbox: context.sandbox)
        let scale = try AnnotateCommand.resolveScale(
            flag: args.scale.map { formatScale($0) },
            document: args.regions.scale
        )
        let resolved = try RegionsResolver.resolve(
            args.regions,
            imagePixelWidth: image.width,
            imagePixelHeight: image.height,
            scale: scale
        )
        let reference = AnnotateCommand.makeReference(resolved, scale: scale)
        let cropRect = CanonicalRect(
            x: 0, y: 0,
            width: CGFloat(image.width) / scale,
            height: CGFloat(image.height) / scale
        )
        guard let rendered = ExportRenderer.renderAnnotatedExport(
            image: image,
            cropRect: cropRect,
            scale: scale,
            measurements: resolved.measurements,
            reference: reference,
            showTotals: args.totals ?? false
        ) else {
            throw CLIError(.generic, "cubit: failed to render annotated image")
        }

        // Validate and canonicalize output paths through the sandbox BEFORE writing.
        var resolvedOutput: String?
        var sidecarPath: String?
        if let outputPath = args.outputPath {
            let outURL = try context.sandbox.resolveForWrite(outputPath)
            do {
                try rendered.png.write(to: outURL)
            } catch {
                throw CLIError(.generic, "cubit: could not write \(outURL.path): \(error.localizedDescription)")
            }
            resolvedOutput = outURL.path
            if args.sidecar == true {
                let sidecarURL = try context.sandbox.resolveForWrite(AnnotateCommand.sidecarURL(forOutput: outURL.path).path)
                do {
                    try rendered.sidecar.jsonData().write(to: sidecarURL)
                    sidecarPath = sidecarURL.path
                } catch {
                    throw CLIError(.generic, "cubit: could not write sidecar: \(error.localizedDescription)")
                }
            }
        }

        let doc = AnnotateResultDoc(
            output: resolvedOutput,
            sidecarPath: sidecarPath,
            scale: Double(scale),
            measurementCount: resolved.measurements.count,
            sidecar: rendered.sidecar
        )
        var content: [ToolContent] = [.text(try prettyJSON(doc))]
        // No output path → hand the PNG back inline so the agent can view it directly.
        if args.outputPath == nil {
            content.append(.image(base64: rendered.png.base64EncodedString(), mimeType: "image/png"))
        }
        return .ok(content)
    }

    // MARK: - show_overlay

    static func showOverlay(_ arguments: JSONValue?) throws -> ToolResult {
        // The arguments ARE the handoff document (canonical proposed measurements). Decode via the
        // shared Core type so the CLI, MCP server, and app can never drift. `open(document:)`
        // validates (schema version, count cap, per-measurement shape), stages a temp file, and
        // opens cubit://show — it never executes anything from the payload.
        let document = try decodeHandoffDocument(arguments)
        let result = try HandoffLauncher.open(document: document)
        let doc = ShowOverlayResultDoc(
            opened: result.path,
            measurementCount: result.count,
            note: document.note,
            status: HandoffStatus.delivered.rawValue,
            statusNote: HandoffStatus.deliveredNote
        )
        return .ok([.text(try prettyJSON(doc))])
    }

    static func decodeHandoffDocument(_ arguments: JSONValue?) throws -> HandoffDocument {
        let value = arguments ?? .object([:])
        let data = try JSONEncoder().encode(value)
        do {
            return try JSONDecoder().decode(HandoffDocument.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw CLIError(.usage, "cubit: missing required argument '\(key.stringValue)'")
        } catch let DecodingError.typeMismatch(_, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw CLIError(.usage, "cubit: argument type mismatch at \(path.isEmpty ? "<root>" : path)")
        } catch {
            throw CLIError(.usage, "cubit: invalid arguments: \(error.localizedDescription)")
        }
    }

    // MARK: - analyze_dead_space

    struct DeadSpaceArgs: Decodable {
        let target: ReferenceArg
        let content: [RegionsInput.Region]
        let scale: Double?
    }

    static func analyzeDeadSpace(_ arguments: JSONValue?) throws -> ToolResult {
        let args = try decodeArguments(arguments, as: DeadSpaceArgs.self)
        guard args.content.count <= MCPLimits.maxRegions else {
            throw MCPToolError.tooLarge("content array has \(args.content.count) items; the limit is \(MCPLimits.maxRegions)")
        }
        if let rect = args.target.rect { try validate(rect) }
        for region in args.content { try validate(region) }
        let ref = try resolveReference(args.target, regionCenter: nil)
        guard ref.rect.area > 0 else {
            throw CLIError(.usage, "cubit: reference area must be positive to analyze dead space")
        }
        let center = CanonicalPoint(
            x: ref.rect.minX + ref.rect.width / 2,
            y: ref.rect.minY + ref.rect.height / 2
        )
        let scale = resolveScale(explicit: args.scale, center: center)

        var breakdown: [DeadSpaceResult.RegionBreakdown] = []
        var usedAreaPoints = 0.0
        for (index, region) in args.content.enumerated() {
            let measurement = try RegionsResolver.measurement(from: region, index: index, scale: 1)
            let metrics = MeasurementEngine.metrics(for: measurement, reference: ref.rect, scale: scale)
            let areaPoints = Double(measurement.rect.area)
            usedAreaPoints += areaPoints
            breakdown.append(DeadSpaceResult.RegionBreakdown(
                index: index,
                label: measurement.label.isEmpty ? nil : measurement.label,
                kind: measurement.kind.rawValue,
                areaPoints: areaPoints,
                areaPixels: Double(metrics.areaPx),
                areaPercent: metrics.areaPercent
            ))
        }

        let refAreaPoints = Double(ref.rect.area)
        let usedPercent = usedAreaPoints / refAreaPoints * 100
        let deadSpacePercent = max(0, 100 - usedPercent)

        let result = DeadSpaceResult(
            reference: DeadSpaceResult.Reference(
                kind: ref.kind,
                name: ref.name,
                rectPoints: DeadSpaceResult.Rect(rect: ref.rect),
                areaPoints: refAreaPoints,
                areaPixels: refAreaPoints * Double(scale) * Double(scale)
            ),
            usedAreaPoints: usedAreaPoints,
            usedAreaPixels: usedAreaPoints * Double(scale) * Double(scale),
            usedPercent: usedPercent,
            deadSpacePercent: deadSpacePercent,
            regionCount: breakdown.count,
            regions: breakdown,
            note: """
            Dead space is pure geometry: 100 − (summed content area ÷ reference area). \
            Overlapping content regions are counted more than once (this measures "how much did \
            I mark", not a de-duplicated union). No content detection is performed — supply the \
            content rectangles you measured.
            """
        )
        return .ok([.text(try prettyJSON(result))])
    }

    // MARK: - Shared resolution

    struct ResolvedRef {
        let rect: CanonicalRect
        let kind: String
        let name: String?
    }

    /// Resolves a reference to a canonical rect. Precedence: explicit rect > window > screen.
    /// When none is supplied and `regionCenter` is non-nil, defaults to the display containing
    /// that point; with no displays at all, throws not-found.
    static func resolveReference(_ reference: ReferenceArg?, regionCenter: CanonicalPoint?) throws -> ResolvedRef {
        if let rect = reference?.rect {
            guard rect.width > 0, rect.height > 0 else {
                throw CLIError(.usage, "cubit: reference rect must have positive width and height")
            }
            return ResolvedRef(rect: canonicalRect(rect), kind: "custom", name: nil)
        }
        if let selector = reference?.window {
            let windows = CGWindowInfoProvider().windows()
            let window = try WindowMatch.find(selector.queryString, in: windows)
            return ResolvedRef(rect: window.canonicalBounds, kind: "window", name: window.ownerName)
        }
        if let index = reference?.screen {
            let displays = Displays.all()
            guard !displays.isEmpty else {
                throw CLIError(.notFound, "cubit: no active displays found")
            }
            guard index >= 0, index < displays.count else {
                throw CLIError(.notFound, "cubit: display index \(index) is out of range (0…\(displays.count - 1))")
            }
            return ResolvedRef(rect: displays[index].frame, kind: "screen", name: "Screen \(index)")
        }
        // Default: the display containing the region's center.
        let displays = Displays.all()
        guard !displays.isEmpty else {
            throw CLIError(.notFound, "cubit: no reference given and no active displays to default to")
        }
        if let center = regionCenter, let hit = displays.first(where: { contains($0.frame, center) }) {
            return ResolvedRef(rect: hit.frame, kind: "screen", name: nil)
        }
        return ResolvedRef(rect: displays[0].frame, kind: "screen", name: nil)
    }

    /// Explicit positive scale wins; otherwise the backing scale of the display containing
    /// `center`, falling back to 2 when there are no displays (headless CI).
    static func resolveScale(explicit: Double?, center: CanonicalPoint) -> CGFloat {
        if let explicit, explicit > 0 { return CGFloat(explicit) }
        guard !Displays.all().isEmpty else { return AnnotateCommand.defaultScale }
        return Displays.scale(containing: center)
    }

    // MARK: - Helpers

    static func decodeArguments<T: Decodable>(_ arguments: JSONValue?, as type: T.Type) throws -> T {
        let value = arguments ?? .object([:])
        let data = try JSONEncoder().encode(value)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw CLIError(.usage, "cubit: missing required argument '\(key.stringValue)'")
        } catch let DecodingError.typeMismatch(_, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw CLIError(.usage, "cubit: argument type mismatch at \(path.isEmpty ? "<root>" : path)")
        } catch {
            throw CLIError(.usage, "cubit: invalid arguments: \(error.localizedDescription)")
        }
    }

    static func loadImage(path: String?, base64: String?, sandbox: PathSandbox) throws -> CGImage {
        switch (path, base64) {
        case (let path?, nil):
            // Confine to the sandbox root, then size-cap before decoding.
            let url = try sandbox.resolveForRead(path)
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > MCPLimits.maxImageFileBytes {
                throw MCPToolError.tooLarge("image file is \(size) bytes; the limit is \(MCPLimits.maxImageFileBytes)")
            }
            return try ImageLoader.load(path: url.path)
        case (nil, let base64?):
            return try decodeImage(base64: base64)
        case (nil, nil):
            throw CLIError(.usage, "cubit: provide either imagePath or imageBase64")
        case (.some, .some):
            throw CLIError(.usage, "cubit: provide only one of imagePath or imageBase64, not both")
        }
    }

    static func decodeImage(base64: String) throws -> CGImage {
        // Tolerate a data: URL prefix and any embedded whitespace/newlines.
        let payload = base64.contains(",") ? String(base64.split(separator: ",", maxSplits: 1).last ?? "") : base64
        // Reject an over-limit payload from its length BEFORE allocating the decoded buffer.
        try ensureImageBase64WithinLimit(payload.count)
        guard let data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]) else {
            throw CLIError(.usage, "cubit: imageBase64 is not valid base64")
        }
        guard data.count <= MCPLimits.maxDecodedImageBytes else {
            throw MCPToolError.tooLarge("decoded image is \(data.count) bytes; the limit is \(MCPLimits.maxDecodedImageBytes)")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CLIError(.usage, "cubit: could not decode imageBase64 as an image")
        }
        return image
    }

    /// Rejects a base64 image whose DECODED size (estimated from the string length, 4 chars → 3
    /// bytes) would exceed the limit, before any buffer is allocated.
    static func ensureImageBase64WithinLimit(_ base64Length: Int) throws {
        let estimatedBytes = base64Length / 4 * 3
        guard estimatedBytes <= MCPLimits.maxDecodedImageBytes else {
            throw MCPToolError.tooLarge("base64 image is ~\(estimatedBytes) bytes decoded; the limit is \(MCPLimits.maxDecodedImageBytes)")
        }
    }

    // MARK: - Coordinate sanity

    /// Rejects non-finite coordinates (NaN / infinity) on a region before it reaches the geometry
    /// engine. JSON itself can't encode NaN/infinity, so this is defense-in-depth.
    static func validate(_ region: RegionsInput.Region) throws {
        if let rect = region.rect { try validate(rect) }
        if let endpoints = region.endpoints {
            for point in endpoints { try requireFinite([point.x, point.y], "endpoint") }
        }
    }

    static func validate(_ rect: RegionsInput.Rect) throws {
        try requireFinite([rect.x, rect.y, rect.width, rect.height], "rect")
    }

    static func requireFinite(_ values: [Double], _ what: String) throws {
        for value in values where !value.isFinite {
            throw CLIError(.usage, "cubit: \(what) has a non-finite coordinate")
        }
    }

    static func canonicalRect(_ rect: RegionsInput.Rect) -> CanonicalRect {
        CanonicalRect(x: CGFloat(rect.x), y: CGFloat(rect.y), width: CGFloat(rect.width), height: CGFloat(rect.height))
    }

    private static func contains(_ rect: CanonicalRect, _ point: CanonicalPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    /// Formats a scale for `AnnotateCommand.resolveScale`, which parses a string flag. Avoids
    /// scientific notation and keeps integers integral ("2", not "2.0e+00").
    static func formatScale(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(value)
    }

    static func prettyJSON(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func schema(_ json: String) -> JSONValue {
        (try? JSONValue.parse(json)) ?? .object([:])
    }
}

// MARK: - Argument sub-models

/// A reference selector shared by measure_region and analyze_dead_space. Provide exactly one of
/// `window` / `screen` / `rect`.
struct ReferenceArg: Decodable, Equatable {
    let window: WindowSelector?
    let screen: Int?
    let rect: RegionsInput.Rect?
}

/// A window reference given as either a window number (integer) or a case-insensitive
/// app/title substring (string).
enum WindowSelector: Decodable, Equatable {
    case number(UInt32)
    case query(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self), number >= 0 {
            self = .number(UInt32(number))
        } else {
            self = .query(try container.decode(String.self))
        }
    }

    /// The string handed to `WindowMatch.find` (which resolves a bare number to a window id).
    var queryString: String {
        switch self {
        case .number(let value): return String(value)
        case .query(let value): return value
        }
    }
}

// MARK: - Result documents

struct MeasureResult: Encodable {
    struct Size: Encodable { let width: Double; let height: Double }
    struct Rect: Encodable {
        let x: Double; let y: Double; let width: Double; let height: Double
        init(rect: CanonicalRect) {
            x = Double(rect.minX); y = Double(rect.minY); width = Double(rect.width); height = Double(rect.height)
        }
    }
    struct Percentages: Encodable { let width: Double; let height: Double; let area: Double; let primary: Double }
    struct Reference: Encodable {
        let kind: String
        let name: String?
        let rectPoints: Rect
        let areaPoints: Double
    }
    let kind: String
    let valueText: String
    let detailText: String
    let sizePoints: Size
    let sizePixels: Size
    let percentages: Percentages
    let reference: Reference
    let scale: Double
}

struct ShowOverlayResultDoc: Encodable {
    /// The staged temp file the app reads (its own JSON document).
    let opened: String
    let measurementCount: Int
    /// The agent's own note, echoed back.
    let note: String?
    /// Always `delivered` — the overlay's appearance cannot be confirmed. See `HandoffStatus`.
    let status: String
    let statusNote: String
}

struct AnnotateResultDoc: Encodable {
    let output: String?
    let sidecarPath: String?
    let scale: Double
    let measurementCount: Int
    let sidecar: MeasurementSidecar
}

struct DeadSpaceResult: Encodable {
    struct Rect: Encodable {
        let x: Double; let y: Double; let width: Double; let height: Double
        init(rect: CanonicalRect) {
            x = Double(rect.minX); y = Double(rect.minY); width = Double(rect.width); height = Double(rect.height)
        }
    }
    struct Reference: Encodable {
        let kind: String
        let name: String?
        let rectPoints: Rect
        let areaPoints: Double
        let areaPixels: Double
    }
    struct RegionBreakdown: Encodable {
        let index: Int
        let label: String?
        let kind: String
        let areaPoints: Double
        let areaPixels: Double
        let areaPercent: Double
    }
    let reference: Reference
    let usedAreaPoints: Double
    let usedAreaPixels: Double
    let usedPercent: Double
    let deadSpacePercent: Double
    let regionCount: Int
    let regions: [RegionBreakdown]
    let note: String
}
