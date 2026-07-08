import XCTest
@testable import Cubit

/// Deterministic text metrics so pill/legend sizing is exact and reproducible.
private struct FakeMeasurer: TextMeasuring {
    var charWidth: CGFloat = 7
    var lineHeight: CGFloat = 14
    /// Scales the fixed per-character metrics by how far `pointSize` sits from the role's
    /// own baseline, so tests that vary point size (markup threading) see a real size delta
    /// while tests using the default `size(of:role:)` convenience stay exactly as before.
    func size(of string: String, role: ExportFontRole, pointSize: CGFloat) -> CGSize {
        let scale = pointSize / role.pointSize
        return CGSize(width: CGFloat(string.count) * charWidth * scale, height: lineHeight * scale)
    }
}

final class AnnotationLayoutEngineTests: XCTestCase {
    private let measuring = FakeMeasurer()
    private let accuracy: CGFloat = 1e-6

    // MARK: Fixtures

    private func legend(rows: Int = 1) -> LegendInput {
        LegendInput(
            headerText: "Window",
            rows: (0..<rows).map { LegendRowInput(colorIndex: $0, labelText: "M", valueText: "50.0%") },
            wordmark: "Cubit",
            metadataHeight: 0
        )
    }

    private func request(
        image: CGSize,
        crop: CanonicalRect? = nil,
        reference: CanonicalRect = CanonicalRect(x: 0, y: 0, width: 1000, height: 800),
        mode: ReferenceMode = .windowUnderCursor,
        callouts: [CalloutInput],
        legend: LegendInput? = nil,
        markup: MarkupStyle = .default
    ) -> LayoutRequest {
        LayoutRequest(
            cropRect: crop ?? CanonicalRect(x: 0, y: 0, width: image.width, height: image.height),
            imageSize: image,
            referenceRect: reference,
            referenceMode: mode,
            callouts: callouts,
            legend: legend ?? self.legend(),
            markup: markup
        )
    }

    private func rectCallout(
        _ rect: CanonicalRect,
        kind: MeasurementKind = .rectangle,
        color: Int = 0,
        label: String? = nil,
        primary: String = "50.0%",
        detail: String = "1024 px"
    ) -> CalloutInput {
        CalloutInput(
            id: UUID(), kind: kind, rect: rect, colorIndex: color,
            labelText: label, primaryText: primary, detailText: detail
        )
    }

    private func pillSize(label: String? = nil, primary: String = "50.0%", detail: String = "1024 px") -> CGSize {
        var widths: [CGFloat] = []
        var height = AnnotationLayoutEngine.pillPaddingV * 2
        var lines = 0
        if let label, !label.isEmpty { widths.append(measuring.size(of: label, role: .calloutLabel).width); height += 14; lines += 1 }
        widths.append(measuring.size(of: primary, role: .calloutPrimary).width); height += 14; lines += 1
        if !detail.isEmpty { widths.append(measuring.size(of: detail, role: .calloutDetail).width); height += 14; lines += 1 }
        height += AnnotationLayoutEngine.pillLineSpacing * CGFloat(max(0, lines - 1))
        return CGSize(width: AnnotationLayoutEngine.pillPaddingH * 2 + (widths.max() ?? 0), height: height)
    }

    // MARK: - Preferred placement

    func testPreferredTopRightWhenFree() {
        let rect = CanonicalRect(x: 400, y: 300, width: 200, height: 150)
        let layout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(rect)]),
            measuring: measuring
        )
        let size = pillSize()
        let callout = layout.callouts[0]
        XCTAssertEqual(callout.frame.origin.x, 600 - size.width, accuracy: accuracy)
        XCTAssertEqual(callout.frame.origin.y, 300 - AnnotationLayoutEngine.calloutGap - size.height, accuracy: accuracy)
        XCTAssertNil(callout.leader, "Adjacent pill needs no leader")
    }

    func testPillFrameSizeMatchesText() {
        let rect = CanonicalRect(x: 400, y: 300, width: 200, height: 150)
        let layout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(rect, label: "Sidebar")]),
            measuring: measuring
        )
        XCTAssertEqual(layout.callouts[0].frame.size, pillSize(label: "Sidebar"))
    }

    // MARK: - Crowded invariants

    func testCrowdedInBoundsInvariant() {
        let layout = AnnotationLayoutEngine.layout(crowdedRequest(), measuring: measuring)
        let bounds = CGRect(origin: .zero, size: layout.imageSize)
        for callout in layout.callouts {
            XCTAssertTrue(bounds.contains(callout.frame), "Callout \(callout.frame) escaped \(bounds)")
        }
    }

    func testCrowdedNoOverlapInvariant() {
        let layout = AnnotationLayoutEngine.layout(crowdedRequest(), measuring: measuring)
        let frames = layout.callouts.map(\.frame)
        for i in frames.indices {
            for j in (i + 1)..<frames.count {
                let inter = frames[i].intersection(frames[j])
                let area = inter.isNull ? 0 : inter.width * inter.height
                XCTAssertLessThanOrEqual(area, 0.01, "Callouts \(i) and \(j) overlap")
            }
        }
    }

    private func crowdedRequest() -> LayoutRequest {
        var callouts: [CalloutInput] = []
        for i in 0..<10 {
            let col = CGFloat(i % 3), row = CGFloat(i / 3)
            let rect = CanonicalRect(x: 40 + col * 110, y: 40 + row * 100, width: 60, height: 45)
            callouts.append(rectCallout(rect, color: i, primary: "99.9%", detail: "123 px"))
        }
        return request(image: CGSize(width: 400, height: 400), callouts: callouts, legend: legend(rows: 10))
    }

    // Window-exact crop: reference == crop == image bounds, and measurements touch the
    // crop edges. Callouts and the legend must still resolve inside the image.
    func testInBoundsWhenReferenceEqualsCropAndMeasurementsAbutEdges() {
        let image = CGSize(width: 320, height: 220)
        let crop = CanonicalRect(x: 0, y: 0, width: 320, height: 220)
        let callouts = [
            rectCallout(CanonicalRect(x: 0, y: 0, width: 130, height: 60), color: 0),        // top-left corner
            rectCallout(CanonicalRect(x: 190, y: 160, width: 130, height: 60), color: 1),    // bottom-right corner
            rectCallout(CanonicalRect(x: 0, y: 100, width: 60, height: 0), kind: .horizontal, color: 2) // left edge
        ]
        let layout = AnnotationLayoutEngine.layout(
            request(image: image, crop: crop, reference: crop, mode: .windowUnderCursor, callouts: callouts, legend: legend(rows: 3)),
            measuring: measuring
        )
        let bounds = CGRect(origin: .zero, size: image)
        for callout in layout.callouts {
            XCTAssertTrue(bounds.contains(callout.frame), "callout \(callout.frame) escaped \(bounds)")
        }
        XCTAssertTrue(bounds.contains(layout.legend.frame), "legend \(layout.legend.frame) escaped \(bounds)")
    }

    // MARK: - Leaders

    func testNoLeaderWhenAdjacent() {
        let rect = CanonicalRect(x: 400, y: 300, width: 200, height: 150)
        let layout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(rect)]),
            measuring: measuring
        )
        XCTAssertNil(layout.callouts[0].leader)
    }

    func testLeaderEmittedWhenDisplaced() {
        // Shape nearly fills the image: every outside-edge candidate exits bounds, forcing
        // an in-shape fallback placement with a leader.
        let rect = CanonicalRect(x: 10, y: 10, width: 180, height: 180)
        let layout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 200, height: 200), callouts: [rectCallout(rect)]),
            measuring: measuring
        )
        let callout = layout.callouts[0]
        XCTAssertNotNil(callout.leader)
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        XCTAssertTrue(bounds.contains(callout.frame))
    }

    // MARK: - Line perpendicular offset

    func testHorizontalCalloutOffsetsPerpendicular() {
        let line = CanonicalRect(x: 400, y: 300, width: 200, height: 0)
        let layout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(line, kind: .horizontal)]),
            measuring: measuring
        )
        let f = layout.callouts[0].frame
        XCTAssertEqual(f.midX, 500, accuracy: accuracy, "Centered on the line midpoint")
        XCTAssertEqual(f.maxY, 300 - AnnotationLayoutEngine.calloutGap, accuracy: accuracy, "Offset above the line")
    }

    func testVerticalCalloutOffsetsPerpendicular() {
        let line = CanonicalRect(x: 400, y: 300, width: 0, height: 150)
        let layout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(line, kind: .vertical)]),
            measuring: measuring
        )
        let f = layout.callouts[0].frame
        XCTAssertEqual(f.minX, 400 + AnnotationLayoutEngine.calloutGap, accuracy: accuracy, "Offset to the right of the line")
        XCTAssertEqual(f.midY, 375, accuracy: accuracy, "Centered on the line midpoint")
    }

    // MARK: - Legend

    func testLegendSizeExact() {
        let input = LegendInput(
            headerText: "REF",
            rows: [
                LegendRowInput(colorIndex: 0, labelText: "AB", valueText: "CDEF"),
                LegendRowInput(colorIndex: 1, labelText: "AB", valueText: "CDEF")
            ],
            wordmark: "Cubit",
            metadataHeight: 0
        )
        // header 3ch=21w; row = 12+6+14+12+28 = 72w; wordmark 5ch=35w → content 72.
        // height: header14 + row14 + row14 + footer14 + 3 gaps*8 = 80; + padding 24.
        XCTAssertEqual(AnnotationLayoutEngine.legendSize(input, measuring: measuring), CGSize(width: 96, height: 104))
    }

    func testLegendDefaultBottomRight() {
        let image = CGSize(width: 1000, height: 800)
        let rect = CanonicalRect(x: 20, y: 20, width: 60, height: 40) // top-left, clear of legend
        let layout = AnnotationLayoutEngine.layout(request(image: image, callouts: [rectCallout(rect)]), measuring: measuring)
        let size = AnnotationLayoutEngine.legendSize(legend(), measuring: measuring)
        XCTAssertEqual(layout.legend.frame.origin.x, 1000 - 24 - size.width, accuracy: accuracy)
        XCTAssertEqual(layout.legend.frame.origin.y, 800 - 24 - size.height, accuracy: accuracy)
    }

    func testLegendFlipsCornerWhenCovering() {
        let image = CGSize(width: 1000, height: 800)
        let legendInput = legend()
        let size = AnnotationLayoutEngine.legendSize(legendInput, measuring: measuring)
        // A measurement occupying exactly the default legend slot → 100% coverage → flip.
        let originX = 1000 - 24 - size.width
        let originY = 800 - 24 - size.height
        let rect = CanonicalRect(x: originX, y: originY, width: size.width, height: size.height)
        let layout = AnnotationLayoutEngine.layout(
            request(image: image, callouts: [rectCallout(rect)], legend: legendInput),
            measuring: measuring
        )
        XCTAssertEqual(layout.legend.frame.origin.x, 24, accuracy: accuracy, "Legend should flip to the left margin")
    }

    // MARK: - Translation & reference outline

    func testShapesTranslatedToExportPoints() {
        let crop = CanonicalRect(x: 100, y: 50, width: 400, height: 400)
        let rect = CanonicalRect(x: 150, y: 80, width: 40, height: 30)
        let layout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 400, height: 400), crop: crop, callouts: [rectCallout(rect)]),
            measuring: measuring
        )
        XCTAssertEqual(layout.shapes[0].rect, CGRect(x: 50, y: 30, width: 40, height: 30))
    }

    func testReferenceOutlineNilForScreenMode() {
        let layout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), mode: .screen,
                    callouts: [rectCallout(CanonicalRect(x: 100, y: 100, width: 50, height: 50))]),
            measuring: measuring
        )
        XCTAssertNil(layout.referenceOutline)
    }

    func testReferenceOutlineTranslatedForWindowMode() {
        let crop = CanonicalRect(x: 100, y: 50, width: 400, height: 400)
        let reference = CanonicalRect(x: 120, y: 70, width: 300, height: 200)
        let layout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 400, height: 400), crop: crop, reference: reference, mode: .windowUnderCursor,
                    callouts: [rectCallout(CanonicalRect(x: 150, y: 90, width: 40, height: 30))]),
            measuring: measuring
        )
        XCTAssertEqual(layout.referenceOutline, CGRect(x: 20, y: 20, width: 300, height: 200))
    }

    // MARK: - M6b metadata footer

    func testFooterHeightZeroWhenMetadataNil() {
        XCTAssertEqual(AnnotationLayoutEngine.footerHeight(nil, measuring: measuring), 0)
    }

    func testFooterHeightZeroWhenNoColumns() {
        let input = MetadataFooterInput(columns: [], wordmark: "Cubit")
        XCTAssertEqual(AnnotationLayoutEngine.footerHeight(input, measuring: measuring), 0)
    }

    func testFooterHeightExactForOneCategoryTwoLines() {
        // caption 14 + gap 4 + 2 lines (14 each) + 1 line-spacing 2 = 48; wordmark 14 -> content max 48.
        let input = MetadataFooterInput(
            columns: [MetadataFooterColumnInput(caption: "Machine", lines: ["line one", "line two"])],
            wordmark: "Cubit"
        )
        let expected = AnnotationLayoutEngine.footerHairlineHeight
            + AnnotationLayoutEngine.footerPadding * 2
            + 48
        XCTAssertEqual(AnnotationLayoutEngine.footerHeight(input, measuring: measuring), expected, accuracy: accuracy)
    }

    func testFooterHeightUsesTallestColumnAcrossTwoCategories() {
        let input = MetadataFooterInput(
            columns: [
                MetadataFooterColumnInput(caption: "Machine", lines: ["a"]),           // 14+4+14 = 32
                MetadataFooterColumnInput(caption: "Window", lines: ["a", "b", "c"])    // 14+4+14+2+14+2+14 = 64
            ],
            wordmark: "Cubit"
        )
        let expected = AnnotationLayoutEngine.footerHairlineHeight
            + AnnotationLayoutEngine.footerPadding * 2
            + 64
        XCTAssertEqual(AnnotationLayoutEngine.footerHeight(input, measuring: measuring), expected, accuracy: accuracy)
    }

    func testFooterHeightThreeCategoriesMatchesTallestOfThree() {
        let input = MetadataFooterInput(
            columns: [
                MetadataFooterColumnInput(caption: "Machine", lines: ["a", "b"]),   // 48
                MetadataFooterColumnInput(caption: "Window", lines: ["a", "b", "c"]), // 64
                MetadataFooterColumnInput(caption: "App", lines: ["a"])              // 32
            ],
            wordmark: "Cubit"
        )
        let expected = AnnotationLayoutEngine.footerHairlineHeight
            + AnnotationLayoutEngine.footerPadding * 2
            + 64
        XCTAssertEqual(AnnotationLayoutEngine.footerHeight(input, measuring: measuring), expected, accuracy: accuracy)
    }

    func testCanvasSizeUnchangedWhenNoFooter() {
        let layout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 400, height: 300), callouts: []),
            measuring: measuring
        )
        XCTAssertNil(layout.footer)
        XCTAssertEqual(layout.canvasSize, CGSize(width: 400, height: 300))
    }

    func testCanvasSizeGrowsByFooterHeightWhenPresent() {
        var req = request(image: CGSize(width: 400, height: 300), callouts: [])
        req.metadataFooter = MetadataFooterInput(
            columns: [MetadataFooterColumnInput(caption: "Machine", lines: ["a"])],
            wordmark: "Cubit"
        )
        let layout = AnnotationLayoutEngine.layout(req, measuring: measuring)
        XCTAssertNotNil(layout.footer)
        let footerHeight = layout.canvasSize.height - layout.imageSize.height
        XCTAssertGreaterThan(footerHeight, 0)
        XCTAssertEqual(layout.footer?.frame.height ?? 0, footerHeight, accuracy: accuracy)
        XCTAssertEqual(layout.footer?.frame.origin.y ?? 0, layout.imageSize.height, accuracy: accuracy)
        XCTAssertEqual(layout.footer?.frame.width ?? 0, layout.imageSize.width, accuracy: accuracy)
    }

    func testGeometryAboveFooterLineUnaffectedByFooterPresence() {
        let rect = CanonicalRect(x: 400, y: 300, width: 200, height: 150)
        let plainLayout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(rect)]),
            measuring: measuring
        )

        var footerReq = request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(rect)])
        footerReq.metadataFooter = MetadataFooterInput(
            columns: [MetadataFooterColumnInput(caption: "Machine", lines: ["a", "b"])],
            wordmark: "Cubit"
        )
        let footerLayout = AnnotationLayoutEngine.layout(footerReq, measuring: measuring)

        XCTAssertEqual(plainLayout.callouts[0].frame, footerLayout.callouts[0].frame)
        XCTAssertEqual(plainLayout.legend.frame, footerLayout.legend.frame)
        XCTAssertEqual(plainLayout.imageSize, footerLayout.imageSize)
    }

    // MARK: - Legend wordmark suppression (footer owns the single wordmark)

    func testLegendSizeOmitsWordmarkRowWhenWordmarkEmpty() {
        let withWordmark = LegendInput(
            headerText: "REF",
            rows: [LegendRowInput(colorIndex: 0, labelText: "AB", valueText: "CDEF")],
            wordmark: "Cubit",
            metadataHeight: 0
        )
        let withoutWordmark = LegendInput(
            headerText: "REF",
            rows: [LegendRowInput(colorIndex: 0, labelText: "AB", valueText: "CDEF")],
            wordmark: "",
            metadataHeight: 0
        )
        let sizeWith = AnnotationLayoutEngine.legendSize(withWordmark, measuring: measuring)
        let sizeWithout = AnnotationLayoutEngine.legendSize(withoutWordmark, measuring: measuring)
        // Dropping the footer row removes one row height (14) and one gap (8).
        XCTAssertEqual(sizeWith.height - sizeWithout.height, 22, accuracy: accuracy)
    }

    // MARK: - Markup threading (export parity with the overlay's border/fill/label settings)

    func testDefaultMarkupMatchesLegacyHardcodedCalloutSizes() {
        // At MarkupStyle.default, callout roles must resolve to exactly the sizes that were
        // hardcoded before markup threading existed (10/13/10), so behavior is unchanged
        // for every user who never touches the Appearance sliders.
        XCTAssertEqual(MarkupStyle.default.calloutLabelPointSize, ExportFontRole.calloutLabel.pointSize)
        XCTAssertEqual(MarkupStyle.default.calloutPrimaryPointSize, ExportFontRole.calloutPrimary.pointSize)
        XCTAssertEqual(MarkupStyle.default.calloutDetailPointSize, ExportFontRole.calloutDetail.pointSize)
    }

    func testLargerLabelPointSizeGrowsCalloutPill() {
        let rect = CanonicalRect(x: 400, y: 300, width: 200, height: 150)
        let smallMarkup = MarkupStyle(borderWidth: 2, fillOpacity: 0.12, labelPointSize: 10)
        let largeMarkup = MarkupStyle(borderWidth: 2, fillOpacity: 0.12, labelPointSize: 13)

        let small = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(rect, label: "Width")], markup: smallMarkup),
            measuring: measuring
        )
        let large = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(rect, label: "Width")], markup: largeMarkup),
            measuring: measuring
        )

        XCTAssertGreaterThan(large.callouts[0].frame.width, small.callouts[0].frame.width)
        XCTAssertGreaterThan(large.callouts[0].frame.height, small.callouts[0].frame.height)
    }

    func testLayoutCarriesMarkupThroughToOutput() {
        let markup = MarkupStyle(borderWidth: 4, fillOpacity: 0.25, labelPointSize: 13)
        let layout = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(CanonicalRect(x: 0, y: 0, width: 100, height: 100))], markup: markup),
            measuring: measuring
        )
        XCTAssertEqual(layout.markup, markup, "renderer reads border/fill/label size off the layout, not a side channel")
    }

    func testLegendAndFooterRolesAreUnaffectedByLabelPointSize() {
        // Only callout text (the export's label pills) scales with labelTextSize; legend,
        // footer, and wordmark chrome are unrelated to measurement labels.
        let rect = CanonicalRect(x: 400, y: 300, width: 200, height: 150)
        let smallMarkup = MarkupStyle(borderWidth: 2, fillOpacity: 0.12, labelPointSize: 10)
        let largeMarkup = MarkupStyle(borderWidth: 2, fillOpacity: 0.12, labelPointSize: 13)

        let small = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(rect)], markup: smallMarkup),
            measuring: measuring
        )
        let large = AnnotationLayoutEngine.layout(
            request(image: CGSize(width: 1000, height: 800), callouts: [rectCallout(rect)], markup: largeMarkup),
            measuring: measuring
        )

        XCTAssertEqual(small.legend.frame.size, large.legend.frame.size)
    }
}
