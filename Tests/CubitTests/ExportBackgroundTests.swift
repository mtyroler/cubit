import XCTest
@testable import Cubit

@MainActor
final class ExportBackgroundTests: XCTestCase {
    // The raw values are the `export.background` UserDefaults contract — renaming a case
    // silently resets every user who picked it. Pin them.
    func testRawValuesAreStable() {
        XCTAssertEqual(ExportBackgroundStyle.transparent.rawValue, "transparent")
        XCTAssertEqual(ExportBackgroundStyle.studio.rawValue, "studio")
        XCTAssertEqual(ExportBackgroundStyle.aurora.rawValue, "aurora")
        XCTAssertEqual(ExportBackgroundStyle.system7.rawValue, "system7")
        XCTAssertEqual(ExportBackgroundStyle.platinum.rawValue, "platinum")
        XCTAssertEqual(ExportBackgroundStyle.aqua.rawValue, "aqua")
        XCTAssertEqual(ExportBackgroundStyle.allCases.count, 6)
    }

    func testBackgroundDefaultsTransparent() {
        let suite = UserDefaults(suiteName: "cubit.test.\(UUID().uuidString)")!
        XCTAssertEqual(ExportLayoutPreferences(defaults: suite).background, .transparent)
        XCTAssertEqual(ExportFraming.default.background, .transparent)
    }

    func testUnknownStoredValueFallsBackToTransparent() {
        let suite = UserDefaults(suiteName: "cubit.test.\(UUID().uuidString)")!
        suite.set("windows-xp", forKey: ExportLayoutPreferences.backgroundKey)
        XCTAssertEqual(ExportLayoutPreferences(defaults: suite).background, .transparent)
    }

    func testBackgroundRoundTripsThroughFraming() {
        let suite = UserDefaults(suiteName: "cubit.test.\(UUID().uuidString)")!
        let prefs = ExportLayoutPreferences(defaults: suite)
        let saved = ExportFraming(includeContext: false, windowShadow: true, background: .platinum)
        prefs.save(saved)
        XCTAssertEqual(prefs.background, .platinum)
        XCTAssertEqual(ExportLayoutPreferences(defaults: suite).framing, saved)
    }

    // MARK: - Chrome metrics (relative sizing invariants)

    // Era bars scale as a fixed fraction of the export height, mirroring each OS's
    // measured bar-to-screen ratio; non-era styles add no chrome.
    func testMenuBarHeightScalesPerEra() {
        let imageSize = CGSize(width: 1440, height: 870)
        // contentHeight = 870 + 40 + 56 = 966
        XCTAssertEqual(ExportBackgroundChrome.menuBarHeight(style: .system7, imageSize: imageSize), 43)
        XCTAssertEqual(ExportBackgroundChrome.menuBarHeight(style: .platinum, imageSize: imageSize), 34)
        XCTAssertEqual(ExportBackgroundChrome.menuBarHeight(style: .aqua, imageSize: imageSize), 29)
        XCTAssertEqual(ExportBackgroundChrome.menuBarHeight(style: .transparent, imageSize: imageSize), 0)
        XCTAssertEqual(ExportBackgroundChrome.menuBarHeight(style: .studio, imageSize: imageSize), 0)
        XCTAssertEqual(ExportBackgroundChrome.menuBarHeight(style: .aurora, imageSize: imageSize), 0)
    }

    func testCheckerPixelIsHalfPointAlignedAndNeverZero() {
        // 1440 + 88 margin = 1528 wide → 1528/640 = 2.3875 → 2.5 after half-point rounding.
        XCTAssertEqual(ExportBackgroundChrome.checkerPixel(imageSize: CGSize(width: 1440, height: 870)), 2.5)
        // Tiny exports clamp to a visible pixel rather than degenerating to zero.
        XCTAssertEqual(ExportBackgroundChrome.checkerPixel(imageSize: CGSize(width: 10, height: 10)), 1)
    }

    func testCornerRadiiFollowEraScreens() {
        let imageSize = CGSize(width: 1240, height: 870) // export width 1240 + 88 = 1328
        let sys7 = ExportBackgroundChrome.cornerRadii(style: .system7, imageSize: imageSize)
        XCTAssertEqual(sys7.topLeading, 1328 * 5 / 640, accuracy: 0.001)
        XCTAssertEqual(sys7.bottomLeading, sys7.topLeading, "System 7 rounded all four corners")

        let platinum = ExportBackgroundChrome.cornerRadii(style: .platinum, imageSize: imageSize)
        XCTAssertEqual(platinum.topLeading, 1328 * 5 / 640, accuracy: 0.001)
        XCTAssertEqual(platinum.bottomLeading, 0, "Platinum rounded the top corners only")

        let aqua = ExportBackgroundChrome.cornerRadii(style: .aqua, imageSize: imageSize)
        XCTAssertEqual(aqua.topLeading, 1328 * 3 / 1024, accuracy: 0.001)
        XCTAssertEqual(aqua.bottomLeading, 0, "Aqua rounded the top corners only")

        let none = ExportBackgroundChrome.cornerRadii(style: .studio, imageSize: imageSize)
        XCTAssertEqual(none.topLeading, 0)
    }

    // MARK: - Render integration

    private static func solidImage(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // Every style renders a styled window export at the exact expected pixel size: the
    // margins are constant, and era styles grow the canvas by exactly their menu bar.
    func testStyledExportRendersEveryBackgroundAtExactSize() throws {
        let scale: CGFloat = 2
        let display = CanonicalRect(x: 0, y: 0, width: 1000, height: 800)
        let captured = CapturedDisplay(
            displayID: 1,
            cgImage: Self.solidImage(width: Int(1000 * scale), height: Int(800 * scale)),
            canonicalFrame: display,
            scale: scale
        )
        let windowRect = CanonicalRect(x: 100, y: 100, width: 400, height: 300)
        let reference = ResolvedReference(rect: windowRect, mode: .windowUnderCursor, descriptor: "Window")
        let windowImage = Self.solidImage(width: Int(400 * scale), height: Int(300 * scale))

        let marginW = WindowExportStyle.sideMargin * 2
        let marginH = WindowExportStyle.topMargin + WindowExportStyle.bottomMargin

        for style in ExportBackgroundStyle.allCases {
            let out = try XCTUnwrap(ExportRenderer.renderCGImage(
                measurements: [],
                reference: reference,
                captured: captured,
                includeContext: false,
                windowShadow: true,
                windowImage: windowImage,
                background: style
            ), "style \(style.rawValue) failed to render")

            let bar = ExportBackgroundChrome.menuBarHeight(style: style, imageSize: CGSize(width: 400, height: 300))
            XCTAssertEqual(out.width, Int((400 + marginW) * scale), "width for \(style.rawValue)")
            XCTAssertEqual(out.height, Int((300 + marginH + bar) * scale), "height for \(style.rawValue)")
        }
    }
}
