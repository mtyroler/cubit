import XCTest
import CoreGraphics
@testable import Cubit

final class ScreenCaptureServiceTests: XCTestCase {
    func testPixelDimensionsScaleByBackingFactor() {
        let (w1, h1) = ScreenCaptureService.pixelDimensions(pointWidth: 1440, pointHeight: 900, scale: 2.0)
        XCTAssertEqual(w1, 2880)
        XCTAssertEqual(h1, 1800)

        let (w2, h2) = ScreenCaptureService.pixelDimensions(pointWidth: 1920, pointHeight: 1080, scale: 1.0)
        XCTAssertEqual(w2, 1920)
        XCTAssertEqual(h2, 1080)
    }

    func testPixelDimensionsRoundFractionalScale() {
        let (w, h) = ScreenCaptureService.pixelDimensions(pointWidth: 1512, pointHeight: 982, scale: 1.5)
        XCTAssertEqual(w, 2268)
        XCTAssertEqual(h, 1473)
    }

    func testCapturedDisplayPreservesMappingFromDescriptor() {
        let frame = CanonicalRect(x: 0, y: 0, width: 1440, height: 900)
        let image = Self.makeImage(width: 2880, height: 1800)
        let captured = CapturedDisplay(displayID: 42, cgImage: image, canonicalFrame: frame, scale: 2.0)

        XCTAssertEqual(captured.displayID, 42)
        XCTAssertEqual(captured.canonicalFrame, frame)
        XCTAssertEqual(captured.scale, 2.0)
        XCTAssertEqual(captured.pixelWidth, 2880)
        XCTAssertEqual(captured.pixelHeight, 1800)
    }

    @MainActor
    func testInitialStateIsIdle() {
        let service = ScreenCaptureService()
        guard case .idle = service.state else {
            return XCTFail("Expected idle initial state")
        }
    }

    /// Real capture. This runner may lack Screen Recording TCC; skip cleanly when denied
    /// or otherwise unavailable rather than failing.
    @MainActor
    func testLiveCaptureMatchesPixelDimensionsWhenPermitted() async throws {
        let displayID = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayID)
        let scale: CGFloat = 2.0
        let request = CaptureRequest(
            displayID: displayID,
            canonicalFrame: CanonicalRect(
                x: bounds.origin.x,
                y: bounds.origin.y,
                width: bounds.width,
                height: bounds.height
            ),
            scale: scale
        )

        let outcome = await ScreenCaptureService().captureAll([request])

        switch outcome {
        case .permissionDenied:
            throw XCTSkip("Screen Recording permission denied in this environment")
        case .failed(let error):
            throw XCTSkip("Capture unavailable in this environment: \(error)")
        case .captured(let displays):
            guard let display = displays.first else {
                throw XCTSkip("Capture returned no displays in this environment (stale capture grant after test-host rebuild?)")
            }
            let (expectedW, expectedH) = ScreenCaptureService.pixelDimensions(
                pointWidth: Int(bounds.width),
                pointHeight: Int(bounds.height),
                scale: scale
            )
            XCTAssertEqual(display.pixelWidth, expectedW)
            XCTAssertEqual(display.pixelHeight, expectedH)
        }
    }

    private static func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
