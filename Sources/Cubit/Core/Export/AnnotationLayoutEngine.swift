import CoreGraphics

/// Pure geometry: turns measurements + reference into fully placed export annotations.
/// No AppKit — text metrics arrive through the injected `TextMeasuring`. Everything it
/// returns is in export-image point coordinates (origin top-left, y-down).
enum AnnotationLayoutEngine {
    // Layout constants (points).
    static let calloutGap: CGFloat = 8
    static let leaderThreshold: CGFloat = 16
    static let pillPaddingH: CGFloat = 8
    static let pillPaddingV: CGFloat = 5
    static let pillLineSpacing: CGFloat = 2
    static let pillCornerInset: CGFloat = 2

    static let legendMargin: CGFloat = 24
    static let legendPadding: CGFloat = 12
    static let legendRowSpacing: CGFloat = 8
    static let legendSwatch: CGFloat = 12
    static let legendSwatchGap: CGFloat = 6
    static let legendLabelValueGap: CGFloat = 12
    static let legendCoverageFlipRatio: CGFloat = 0.30

    // M6b metadata footer (8pt grid).
    static let footerHairlineHeight: CGFloat = 1
    static let footerPadding: CGFloat = 16
    static let footerColumnGap: CGFloat = 24
    static let footerCaptionLineGap: CGFloat = 4
    static let footerLineSpacing: CGFloat = 2

    static func layout(_ request: LayoutRequest, measuring: TextMeasuring) -> ExportLayout {
        let bounds = CGRect(origin: .zero, size: request.imageSize)
        let cropOrigin = request.cropRect.origin

        let shapes = request.callouts.map { input in
            ShapeGeometry(
                id: input.id,
                kind: input.kind,
                rect: translate(input.rect, cropOrigin: cropOrigin),
                colorIndex: input.colorIndex
            )
        }

        let legend = layoutLegend(request.legend, shapes: shapes, bounds: bounds, measuring: measuring)

        // Obstacles the pills should avoid: every shape, plus the legend card.
        var obstacles = shapes.map(\.rect)
        obstacles.append(legend.frame)

        let callouts = placeCallouts(
            request.callouts,
            shapes: shapes,
            obstacles: obstacles,
            bounds: bounds,
            markup: request.markup,
            measuring: measuring
        )

        let referenceOutline: CGRect? = request.referenceMode == .screen
            ? nil
            : translate(request.referenceRect, cropOrigin: cropOrigin)

        let footer = layoutFooter(request.metadataFooter, imageSize: request.imageSize, measuring: measuring)
        let canvasSize = CGSize(
            width: request.imageSize.width,
            height: request.imageSize.height + (footer?.frame.height ?? 0)
        )

        return ExportLayout(
            imageSize: request.imageSize,
            canvasSize: canvasSize,
            shapes: shapes,
            callouts: callouts,
            legend: legend,
            referenceOutline: referenceOutline,
            footer: footer,
            markup: request.markup
        )
    }

    // MARK: - Translation

    private static func translate(_ rect: CanonicalRect, cropOrigin: CanonicalPoint) -> CGRect {
        CGRect(
            x: rect.minX - cropOrigin.x,
            y: rect.minY - cropOrigin.y,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: - Callout pills

    private static func pillSize(for input: CalloutInput, markup: MarkupStyle, measuring: TextMeasuring) -> CGSize {
        var lineWidths: [CGFloat] = []
        var height = pillPaddingV * 2
        var lineCount = 0

        if let label = input.labelText, !label.isEmpty {
            let s = measuring.size(of: label, role: .calloutLabel, pointSize: markup.calloutLabelPointSize)
            lineWidths.append(s.width)
            height += s.height
            lineCount += 1
        }
        let primary = measuring.size(of: input.primaryText, role: .calloutPrimary, pointSize: markup.calloutPrimaryPointSize)
        lineWidths.append(primary.width)
        height += primary.height
        lineCount += 1

        if !input.detailText.isEmpty {
            let detail = measuring.size(of: input.detailText, role: .calloutDetail, pointSize: markup.calloutDetailPointSize)
            lineWidths.append(detail.width)
            height += detail.height
            lineCount += 1
        }

        height += pillLineSpacing * CGFloat(max(0, lineCount - 1))
        let width = pillPaddingH * 2 + (lineWidths.max() ?? 0)
        return CGSize(width: width, height: height)
    }

    private static func placeCallouts(
        _ inputs: [CalloutInput],
        shapes: [ShapeGeometry],
        obstacles: [CGRect],
        bounds: CGRect,
        markup: MarkupStyle,
        measuring: TextMeasuring
    ) -> [PlacedCallout] {
        var placedFrames: [CGRect] = []
        var result: [PlacedCallout] = []

        for (input, shape) in zip(inputs, shapes) {
            let size = pillSize(for: input, markup: markup, measuring: measuring)
            let candidates = candidateOrigins(for: shape, pillSize: size)

            var chosen: CGRect?
            for origin in candidates {
                let frame = CGRect(origin: origin, size: size)
                guard bounds.contains(frame) else { continue }
                guard !overlapsAny(frame, placedFrames) else { continue }
                guard !overlapsAny(frame, obstacles) else { continue }
                chosen = frame
                break
            }

            let frame: CGRect
            let leader: Leader?
            if let chosen {
                frame = chosen
                leader = leaderIfNeeded(pill: chosen, shape: shape.rect)
            } else {
                let fallback = fallbackFrame(
                    size: size,
                    shape: shape.rect,
                    placedFrames: placedFrames,
                    obstacles: obstacles,
                    bounds: bounds
                )
                frame = fallback
                leader = makeLeader(pill: fallback, shape: shape.rect)
            }

            placedFrames.append(frame)
            result.append(PlacedCallout(
                id: input.id,
                frame: frame,
                colorIndex: input.colorIndex,
                labelText: input.labelText,
                primaryText: input.primaryText,
                detailText: input.detailText,
                leader: leader
            ))
        }
        return result
    }

    /// Eight anchor positions around a shape, best first. Rectangles prefer top-right;
    /// lines offset perpendicular to their axis.
    private static func candidateOrigins(for shape: ShapeGeometry, pillSize s: CGSize) -> [CGPoint] {
        let r = shape.rect
        let g = calloutGap
        switch shape.kind {
        case .rectangle:
            return [
                CGPoint(x: r.maxX - s.width, y: r.minY - g - s.height), // top-right (preferred)
                CGPoint(x: r.minX, y: r.minY - g - s.height),           // top-left
                CGPoint(x: r.maxX + g, y: r.minY),                      // right-top
                CGPoint(x: r.maxX + g, y: r.maxY - s.height),           // right-bottom
                CGPoint(x: r.maxX - s.width, y: r.maxY + g),            // bottom-right
                CGPoint(x: r.minX, y: r.maxY + g),                      // bottom-left
                CGPoint(x: r.minX - g - s.width, y: r.minY),            // left-top
                CGPoint(x: r.minX - g - s.width, y: r.maxY - s.height)  // left-bottom
            ]
        case .horizontal:
            let y = r.minY
            return [
                CGPoint(x: r.midX - s.width / 2, y: y - g - s.height),  // above-center (preferred)
                CGPoint(x: r.midX - s.width / 2, y: y + g),             // below-center
                CGPoint(x: r.maxX - s.width, y: y - g - s.height),      // above-right
                CGPoint(x: r.minX, y: y - g - s.height),                // above-left
                CGPoint(x: r.maxX - s.width, y: y + g),                 // below-right
                CGPoint(x: r.minX, y: y + g),                           // below-left
                CGPoint(x: r.maxX + g, y: y - s.height / 2),            // right
                CGPoint(x: r.minX - g - s.width, y: y - s.height / 2)   // left
            ]
        case .vertical:
            let x = r.minX
            return [
                CGPoint(x: x + g, y: r.midY - s.height / 2),            // right-center (preferred)
                CGPoint(x: x - g - s.width, y: r.midY - s.height / 2),  // left-center
                CGPoint(x: x + g, y: r.minY),                           // right-top
                CGPoint(x: x + g, y: r.maxY - s.height),               // right-bottom
                CGPoint(x: x - g - s.width, y: r.minY),                 // left-top
                CGPoint(x: x - g - s.width, y: r.maxY - s.height),      // left-bottom
                CGPoint(x: x - s.width / 2, y: r.minY - g - s.height),  // above
                CGPoint(x: x - s.width / 2, y: r.maxY + g)              // below
            ]
        }
    }

    /// Grid search across the whole image for an in-bounds cell that doesn't overlap any
    /// already-placed pill. Guarantees the pill-vs-pill no-overlap and in-bounds invariants;
    /// prefers cells that also miss the shapes/legend and sit near the owning shape.
    private static func fallbackFrame(
        size: CGSize,
        shape: CGRect,
        placedFrames: [CGRect],
        obstacles: [CGRect],
        bounds: CGRect
    ) -> CGRect {
        let step: CGFloat = 8
        let anchor = nearestPoint(on: shape, to: CGPoint(x: shape.midX, y: shape.midY))
        var best: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude

        var y = bounds.minY
        while y + size.height <= bounds.maxY {
            var x = bounds.minX
            while x + size.width <= bounds.maxX {
                let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
                if !overlapsAny(frame, placedFrames) {
                    let obstacleArea = obstacles.reduce(CGFloat.zero) { $0 + overlapArea(frame, $1) }
                    let center = CGPoint(x: frame.midX, y: frame.midY)
                    let dist = hypot(center.x - anchor.x, center.y - anchor.y)
                    let score = obstacleArea * 1000 + dist
                    if score < bestScore {
                        bestScore = score
                        best = frame
                    }
                }
                x += step
            }
            y += step
        }

        // Nothing fits (image smaller than pill): clamp into bounds as a last resort.
        return best ?? CGRect(
            x: min(max(bounds.minX, shape.minX), bounds.maxX - size.width),
            y: min(max(bounds.minY, shape.minY), bounds.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    private static func leaderIfNeeded(pill: CGRect, shape: CGRect) -> Leader? {
        let gap = gapDistance(from: pill, to: shape)
        guard gap > leaderThreshold else { return nil }
        return makeLeader(pill: pill, shape: shape)
    }

    private static func makeLeader(pill: CGRect, shape: CGRect) -> Leader {
        let pillCenter = CGPoint(x: pill.midX, y: pill.midY)
        let end = nearestPoint(on: shape, to: pillCenter)
        let start = nearestPoint(on: pill, to: end)
        return Leader(start: start, end: end)
    }

    // MARK: - Legend

    private static func layoutLegend(
        _ input: LegendInput,
        shapes: [ShapeGeometry],
        bounds: CGRect,
        measuring: TextMeasuring
    ) -> LegendGeometry {
        let size = legendSize(input, measuring: measuring)

        let rightOrigin = CGPoint(
            x: bounds.maxX - legendMargin - size.width,
            y: bounds.maxY - legendMargin - size.height
        )
        var frame = CGRect(origin: rightOrigin, size: size)

        if coversTooMuch(frame, shapes: shapes) {
            frame.origin.x = bounds.minX + legendMargin
        }

        return LegendGeometry(
            frame: frame,
            headerText: input.headerText,
            rows: input.rows,
            totals: input.totals,
            wordmark: input.wordmark,
            metadataHeight: input.metadataHeight
        )
    }

    /// Exact card size: padding, header, one row per measurement, footer (wordmark +
    /// reserved metadata), with `legendRowSpacing` between every stacked element. The
    /// wordmark row (and its gap) is omitted entirely when `wordmark` is empty — the M6b
    /// footer owns the wordmark instead, and exactly one copy is ever drawn.
    static func legendSize(_ input: LegendInput, measuring: TextMeasuring) -> CGSize {
        let header = measuring.size(of: input.headerText, role: .legendHeader)
        var maxContentWidth = header.width
        var elementHeights: [CGFloat] = [header.height]

        for row in input.rows {
            let label = measuring.size(of: row.labelText, role: .legendLabel)
            let value = measuring.size(of: row.valueText, role: .legendValue)
            let rowHeight = max(legendSwatch, max(label.height, value.height))
            let rowWidth = legendSwatch + legendSwatchGap + label.width + legendLabelValueGap + value.width
            maxContentWidth = max(maxContentWidth, rowWidth)
            elementHeights.append(rowHeight)
        }

        // Total lines are swatch-less single lines below the rows, measured at the value role
        // (the same font the card renders them with) so the card sizes exactly.
        for total in input.totals {
            let line = measuring.size(of: total, role: .legendValue)
            maxContentWidth = max(maxContentWidth, line.width)
            elementHeights.append(line.height)
        }

        let hasWordmark = !input.wordmark.isEmpty
        if hasWordmark || input.metadataHeight > 0 {
            let wordmark = measuring.size(of: input.wordmark, role: .wordmark)
            let footerHeight = wordmark.height + input.metadataHeight
            maxContentWidth = max(maxContentWidth, wordmark.width)
            elementHeights.append(footerHeight)
        }

        let totalHeight = elementHeights.reduce(0, +)
            + legendRowSpacing * CGFloat(max(0, elementHeights.count - 1))

        return CGSize(
            width: maxContentWidth + legendPadding * 2,
            height: totalHeight + legendPadding * 2
        )
    }

    // MARK: - Metadata footer

    private static func layoutFooter(
        _ input: MetadataFooterInput?,
        imageSize: CGSize,
        measuring: TextMeasuring
    ) -> FooterGeometry? {
        guard let input, !input.columns.isEmpty else { return nil }
        let height = footerHeight(input, measuring: measuring)
        guard height > 0 else { return nil }
        let frame = CGRect(x: 0, y: imageSize.height, width: imageSize.width, height: height)
        return FooterGeometry(frame: frame, columns: input.columns, wordmark: input.wordmark)
    }

    /// Pure function of the enabled categories and their line counts. Zero when there are
    /// no columns — the canvas height is then identical to `imageSize.height`.
    static func footerHeight(_ input: MetadataFooterInput?, measuring: TextMeasuring) -> CGFloat {
        guard let input, !input.columns.isEmpty else { return 0 }

        var maxColumnHeight: CGFloat = 0
        for column in input.columns {
            var height = measuring.size(of: column.caption, role: .footerCaption).height
            height += footerCaptionLineGap
            for (index, line) in column.lines.enumerated() {
                if index > 0 { height += footerLineSpacing }
                height += measuring.size(of: line, role: .footerLine).height
            }
            maxColumnHeight = max(maxColumnHeight, height)
        }

        let wordmarkHeight = input.wordmark.isEmpty
            ? 0
            : measuring.size(of: input.wordmark, role: .wordmark).height
        let contentHeight = max(maxColumnHeight, wordmarkHeight)

        return footerHairlineHeight + footerPadding * 2 + contentHeight
    }

    private static func coversTooMuch(_ frame: CGRect, shapes: [ShapeGeometry]) -> Bool {
        let totalArea = shapes.reduce(CGFloat.zero) { $0 + $1.rect.width * $1.rect.height }
        guard totalArea > 0 else { return false }
        let covered = shapes.reduce(CGFloat.zero) { $0 + overlapArea(frame, $1.rect) }
        return covered > legendCoverageFlipRatio * totalArea
    }

    // MARK: - Geometry helpers

    private static func overlapsAny(_ frame: CGRect, _ rects: [CGRect]) -> Bool {
        for r in rects where overlapArea(frame, r) > 0.01 { return true }
        return false
    }

    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        return i.width * i.height
    }

    /// Clamp `point` to the rect (works for degenerate line rects too).
    private static func nearestPoint(on rect: CGRect, to point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    /// Distance between the nearest points of two rects; 0 if they touch or overlap.
    private static func gapDistance(from a: CGRect, to b: CGRect) -> CGFloat {
        let dx = max(0, max(b.minX - a.maxX, a.minX - b.maxX))
        let dy = max(0, max(b.minY - a.maxY, a.minY - b.maxY))
        return hypot(dx, dy)
    }
}
