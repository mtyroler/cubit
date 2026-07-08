import CoreGraphics
import Foundation
import ScreenCaptureKit

struct CapturedDisplay: @unchecked Sendable {
    let displayID: CGDirectDisplayID
    let cgImage: CGImage
    let canonicalFrame: CanonicalRect
    let scale: CGFloat

    var pixelWidth: Int { cgImage.width }
    var pixelHeight: Int { cgImage.height }
}

struct CaptureRequest: Sendable {
    let displayID: CGDirectDisplayID
    let canonicalFrame: CanonicalRect
    let scale: CGFloat
}

enum CaptureOutcome: @unchecked Sendable {
    case captured([CapturedDisplay])
    case permissionDenied
    case failed(Error)
}

@MainActor
final class ScreenCaptureService {
    enum State: @unchecked Sendable {
        case idle
        case capturing
        case captured
        case permissionDenied
        case failed(Error)
    }

    private(set) var state: State = .idle

    /// Captures every requested display once. Intended to run at overlay entry, before
    /// (or concurrently with) the overlay windows ordering front — our own windows are
    /// excluded from the content filter so the snapshot never contains the overlay.
    func captureAll(_ requests: [CaptureRequest]) async -> CaptureOutcome {
        state = .capturing
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let ourPID = ProcessInfo.processInfo.processIdentifier
            let ourWindows = content.windows.filter { $0.owningApplication?.processID == ourPID }

            var results: [CapturedDisplay] = []
            for request in requests {
                guard let display = content.displays.first(where: { $0.displayID == request.displayID }) else {
                    continue
                }
                let filter = SCContentFilter(display: display, excludingWindows: ourWindows)
                let (pixelWidth, pixelHeight) = Self.pixelDimensions(
                    pointWidth: display.width,
                    pointHeight: display.height,
                    scale: request.scale
                )
                let config = SCStreamConfiguration()
                config.width = pixelWidth
                config.height = pixelHeight
                config.captureResolution = .best
                config.showsCursor = false

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                results.append(CapturedDisplay(
                    displayID: request.displayID,
                    cgImage: image,
                    canonicalFrame: request.canonicalFrame,
                    scale: request.scale
                ))
            }
            state = .captured
            return .captured(results)
        } catch {
            if Self.isPermissionDenied(error) {
                state = .permissionDenied
                return .permissionDenied
            }
            state = .failed(error)
            return .failed(error)
        }
    }

    /// Pixel dimensions for a display given its point size and backing scale.
    nonisolated static func pixelDimensions(pointWidth: Int, pointHeight: Int, scale: CGFloat) -> (Int, Int) {
        let width = Int((CGFloat(pointWidth) * scale).rounded())
        let height = Int((CGFloat(pointHeight) * scale).rounded())
        return (width, height)
    }

    nonisolated static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userDeclined.rawValue
    }
}
