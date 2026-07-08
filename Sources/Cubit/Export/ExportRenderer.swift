import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Turns a captured display + a measurement session into a designed, annotated PNG.
/// Owns the crop policy and drives the pure layout engine, the SwiftUI renderer, and
/// metadata-free PNG encoding.
@MainActor
enum ExportRenderer {
    /// Context padding around a window/custom reference so it doesn't sit flush to the edge.
    static let cropPadding: CGFloat = 48

    /// Renders the annotated image as a CGImage at the display's native pixel resolution.
    /// `metadata` is empty by default — exports carry zero identifying content unless the
    /// caller explicitly opts in (M6b).
    static func renderCGImage(
        measurements: [Measurement],
        reference: ResolvedReference,
        captured: CapturedDisplay,
        includeContext: Bool = false,
        windowShadow: Bool = true,
        metadata: ExportMetadata = ExportMetadata(),
        markup: MarkupStyle = .default,
        windowImage: CGImage? = nil,
        showTotals: Bool = false
    ) -> CGImage? {
        let scale = captured.scale
        let displayFrame = captured.canonicalFrame

        // Exact-window export with a clean window capture available: use the window's own
        // pixels (occlusion-free) instead of cropping the composited display snapshot, which
        // would bake in whatever window was stacked on top. Context/screen/custom exports keep
        // the display-snapshot crop — their whole point is the surrounding desktop.
        if let windowImage, reference.mode == .windowUnderCursor, !includeContext {
            return renderWindowImage(
                windowImage,
                measurements: measurements,
                reference: reference,
                scale: scale,
                windowShadow: windowShadow,
                metadata: metadata,
                markup: markup,
                showTotals: showTotals
            )
        }

        let cropCanonical = cropRect(reference: reference, displayFrame: displayFrame, includeContext: includeContext)

        // Crop the captured pixels. CGImage is top-left origin, matching display-local canonical.
        let local = CGRect(
            x: (cropCanonical.minX - displayFrame.minX) * scale,
            y: (cropCanonical.minY - displayFrame.minY) * scale,
            width: cropCanonical.width * scale,
            height: cropCanonical.height * scale
        ).integral
        let imageBounds = CGRect(x: 0, y: 0, width: captured.cgImage.width, height: captured.cgImage.height)
        let pixelCrop = local.intersection(imageBounds)
        guard !pixelCrop.isNull, pixelCrop.width > 0, pixelCrop.height > 0,
              let cropped = captured.cgImage.cropping(to: pixelCrop) else { return nil }

        // Derive the exact point-space crop back from the integral pixel rect.
        let pointSize = CGSize(width: pixelCrop.width / scale, height: pixelCrop.height / scale)
        let cropForEngine = CanonicalRect(
            origin: CanonicalPoint(
                x: displayFrame.minX + pixelCrop.minX / scale,
                y: displayFrame.minY + pixelCrop.minY / scale
            ),
            width: pointSize.width,
            height: pointSize.height
        )

        let request = buildRequest(
            measurements: measurements,
            reference: reference,
            scale: scale,
            cropRect: cropForEngine,
            imageSize: pointSize,
            metadata: metadata,
            markup: markup,
            showTotals: showTotals
        )
        let layout = AnnotationLayoutEngine.layout(request, measuring: AttributedStringMeasurer())

        // Native-window styling (rounded corners + shadow in transparent margins) applies to
        // an exact window crop only — never a padded context shot or a screen/custom region.
        let styled = windowStyled(mode: reference.mode, includeContext: includeContext, windowShadow: windowShadow)
        if styled {
            let renderer = ImageRenderer(content: StyledWindowExportView(layout: layout, image: cropped))
            renderer.scale = scale
            renderer.isOpaque = false
            return renderer.cgImage
        }
        let renderer = ImageRenderer(content: ScreenshotAnnotationView(layout: layout, image: cropped))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    /// Renders an annotated export from a clean, occlusion-free window capture. The image IS
    /// the reference window at native resolution, so the crop rect is simply the window bounds
    /// and annotations (in canonical space) map directly onto it — no display-snapshot crop.
    private static func renderWindowImage(
        _ image: CGImage,
        measurements: [Measurement],
        reference: ResolvedReference,
        scale: CGFloat,
        windowShadow: Bool,
        metadata: ExportMetadata,
        markup: MarkupStyle,
        showTotals: Bool
    ) -> CGImage? {
        let pointSize = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let cropRect = CanonicalRect(origin: reference.rect.origin, width: pointSize.width, height: pointSize.height)

        let request = buildRequest(
            measurements: measurements,
            reference: reference,
            scale: scale,
            cropRect: cropRect,
            imageSize: pointSize,
            metadata: metadata,
            markup: markup,
            showTotals: showTotals
        )
        let layout = AnnotationLayoutEngine.layout(request, measuring: AttributedStringMeasurer())

        // A single-window capture carries transparent rounded corners, so the render is never
        // opaque. The shadow toggle picks the native-window framing vs. a plain annotated crop.
        if windowShadow {
            let renderer = ImageRenderer(content: StyledWindowExportView(layout: layout, image: image))
            renderer.scale = scale
            renderer.isOpaque = false
            return renderer.cgImage
        }
        let renderer = ImageRenderer(content: ScreenshotAnnotationView(layout: layout, image: image))
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.cgImage
    }

    /// Native-window styling is on only for an exact window crop with the shadow toggle on.
    static func windowStyled(mode: ReferenceMode, includeContext: Bool, windowShadow: Bool) -> Bool {
        mode == .windowUnderCursor && !includeContext && windowShadow
    }

    /// Renders and encodes to metadata-free PNG data. "Metadata-free" refers to the PNG
    /// container (no EXIF/DPI/text chunks) and is unrelated to the optional `metadata`
    /// imprint, which — when non-empty — is baked into the pixels themselves as a footer.
    static func renderPNG(
        measurements: [Measurement],
        reference: ResolvedReference,
        captured: CapturedDisplay,
        includeContext: Bool = false,
        windowShadow: Bool = true,
        metadata: ExportMetadata = ExportMetadata(),
        markup: MarkupStyle = .default,
        windowImage: CGImage? = nil,
        showTotals: Bool = false
    ) -> Data? {
        guard let image = renderCGImage(
            measurements: measurements,
            reference: reference,
            captured: captured,
            includeContext: includeContext,
            windowShadow: windowShadow,
            metadata: metadata,
            markup: markup,
            windowImage: windowImage,
            showTotals: showTotals
        ) else {
            return nil
        }
        return pngData(from: image)
    }

    /// The captured display that owns the reference (v0.1: the one containing its center).
    static func captured(for reference: ResolvedReference, in displays: [CapturedDisplay]) -> CapturedDisplay? {
        let center = CanonicalPoint(
            x: reference.rect.minX + reference.rect.width / 2,
            y: reference.rect.minY + reference.rect.height / 2
        )
        return displays.first { contains($0.canonicalFrame, center) } ?? displays.first
    }

    // MARK: - Crop policy

    /// Window/custom exports crop to the reference rect EXACTLY (window-only, no desktop) by
    /// default; `includeContext` restores the padded-with-surroundings framing. Screen mode
    /// is always the full display. Everything is clamped to the captured display.
    static func cropRect(
        reference: ResolvedReference,
        displayFrame: CanonicalRect,
        includeContext: Bool
    ) -> CanonicalRect {
        guard reference.mode != .screen else { return displayFrame }
        guard includeContext else { return clamp(reference.rect, to: displayFrame) }
        let expanded = CanonicalRect(
            x: reference.rect.minX - cropPadding,
            y: reference.rect.minY - cropPadding,
            width: reference.rect.width + cropPadding * 2,
            height: reference.rect.height + cropPadding * 2
        )
        return clamp(expanded, to: displayFrame)
    }

    // MARK: - Request composition (strings live here, not in Core)

    private static func buildRequest(
        measurements: [Measurement],
        reference: ResolvedReference,
        scale: CGFloat,
        cropRect: CanonicalRect,
        imageSize: CGSize,
        metadata: ExportMetadata,
        markup: MarkupStyle,
        showTotals: Bool
    ) -> LayoutRequest {
        var callouts: [CalloutInput] = []
        var rows: [LegendRowInput] = []

        for (index, measurement) in measurements.enumerated() {
            let metrics = MeasurementEngine.metrics(for: measurement, reference: reference.rect, scale: scale)
            let primary = primaryText(metrics)
            let detail = detailText(kind: measurement.kind, metrics: metrics)
            let label = measurement.label.isEmpty ? nil : measurement.label

            callouts.append(CalloutInput(
                id: measurement.id,
                kind: measurement.kind,
                rect: measurement.rect,
                colorIndex: measurement.colorIndex,
                labelText: label,
                primaryText: primary,
                detailText: detail
            ))
            rows.append(LegendRowInput(
                colorIndex: measurement.colorIndex,
                labelText: label ?? "Measurement \(index + 1)",
                valueText: "\(primary)  ·  \(detail)"
            ))
        }

        // Exactly one wordmark ever renders: the footer owns it when metadata is present,
        // otherwise it stays in the legend card.
        let hasFooter = !metadata.isEmpty
        let legend = LegendInput(
            headerText: reference.descriptor,
            rows: rows,
            totals: showTotals ? measurementTotals(measurements, reference: reference.rect, scale: scale) : [],
            wordmark: hasFooter ? "" : "Cubit",
            metadataHeight: 0
        )
        return LayoutRequest(
            cropRect: cropRect,
            imageSize: imageSize,
            referenceRect: reference.rect,
            referenceMode: reference.mode,
            callouts: callouts,
            legend: legend,
            metadataFooter: hasFooter ? metadataFooter(from: metadata) : nil,
            markup: markup
        )
    }

    private static func metadataFooter(from metadata: ExportMetadata) -> MetadataFooterInput {
        var columns: [MetadataFooterColumnInput] = []
        if let machine = metadata.machine {
            columns.append(MetadataFooterColumnInput(caption: "Machine", lines: machine.lines))
        }
        if let window = metadata.window {
            columns.append(MetadataFooterColumnInput(caption: "Window", lines: window.lines))
        }
        if let app = metadata.app {
            columns.append(MetadataFooterColumnInput(caption: "App", lines: app.lines))
        }
        return MetadataFooterInput(columns: columns, wordmark: "Cubit")
    }

    /// Summed totals per measurement kind, one legend line each, only for kinds with at least
    /// two measurements (a single one already shows its own value in its row). Rectangles total
    /// their area %, horizontal lines their combined width % and pixel length, vertical lines
    /// their combined height % and pixel length. Sums are arithmetic — overlapping shapes are
    /// counted more than once, matching "how much did I mark", not a de-duplicated union.
    static func measurementTotals(_ measurements: [Measurement], reference: CanonicalRect, scale: CGFloat) -> [String] {
        var rectPercent = 0.0, rectCount = 0
        var hPercent = 0.0, hLength: CGFloat = 0, hCount = 0
        var vPercent = 0.0, vLength: CGFloat = 0, vCount = 0

        for measurement in measurements {
            let metrics = MeasurementEngine.metrics(for: measurement, reference: reference, scale: scale)
            switch measurement.kind {
            case .rectangle:
                rectPercent += metrics.areaPercent
                rectCount += 1
            case .horizontal:
                hPercent += metrics.widthPercent
                hLength += metrics.lengthPx
                hCount += 1
            case .vertical:
                vPercent += metrics.heightPercent
                vLength += metrics.lengthPx
                vCount += 1
            }
        }

        var lines: [String] = []
        if rectCount >= 2 {
            lines.append(String(format: "Total area  ·  %.1f%%", rectPercent))
        }
        if hCount >= 2 {
            lines.append(String(format: "Total width  ·  %.1f%%  ·  %d px", hPercent, Int(hLength.rounded())))
        }
        if vCount >= 2 {
            lines.append(String(format: "Total height  ·  %.1f%%  ·  %d px", vPercent, Int(vLength.rounded())))
        }
        return lines
    }

    static func primaryText(_ metrics: Metrics) -> String {
        String(format: "%.1f%%", metrics.primaryPercent)
    }

    static func detailText(kind: MeasurementKind, metrics: Metrics) -> String {
        switch kind {
        case .rectangle:
            return "\(Int(metrics.widthPx.rounded()))×\(Int(metrics.heightPx.rounded())) px"
        case .horizontal, .vertical:
            return "\(Int(metrics.lengthPx.rounded())) px"
        }
    }

    // MARK: - PNG encoding (no DPI, no EXIF, no metadata)

    static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [:] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return stripMetadata(from: data as Data)
    }

    /// ImageIO still emits an `eXIf` chunk even with empty properties. Filter every
    /// metadata-bearing ancillary chunk out of the byte stream so the PNG carries pixels,
    /// color, and transparency only — no EXIF, no DPI, no text, no timestamps.
    static func stripMetadata(from png: Data) -> Data {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let bytes = [UInt8](png)
        guard bytes.count > 8, Array(bytes.prefix(8)) == signature else { return png }
        let strip: Set<String> = ["eXIf", "tEXt", "iTXt", "zTXt", "pHYs", "tIME", "iCCP"]

        var out = Data(signature)
        var i = 8
        while i + 12 <= bytes.count {
            let length = Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            let chunkEnd = i + 12 + length
            guard chunkEnd <= bytes.count else { break }
            let type = String(bytes: bytes[(i + 4)..<(i + 8)], encoding: .ascii) ?? ""
            if !strip.contains(type) {
                out.append(contentsOf: bytes[i..<chunkEnd])
            }
            i = chunkEnd
            if type == "IEND" { break }
        }
        return out
    }

    // MARK: - Canonical geometry helpers

    private static func clamp(_ rect: CanonicalRect, to bounds: CanonicalRect) -> CanonicalRect {
        let minX = max(rect.minX, bounds.minX)
        let minY = max(rect.minY, bounds.minY)
        let maxX = min(rect.maxX, bounds.maxX)
        let maxY = min(rect.maxY, bounds.maxY)
        return CanonicalRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private static func contains(_ rect: CanonicalRect, _ point: CanonicalPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
