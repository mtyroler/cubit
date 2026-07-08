import CoreGraphics
import Foundation

struct CGWindowInfoProvider: WindowInfoProviding {
    func windows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return raw.compactMap { info in
            guard
                let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                let layer = info[kCGWindowLayer as String] as? Int,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                let windowID = info[kCGWindowNumber as String] as? UInt32
            else {
                return nil
            }

            // kCGWindowBounds is already CG-global, top-left origin, in points — no flip.
            let canonical = CanonicalRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height)
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            // kCGWindowName is commonly nil without Screen Recording permission.
            let title = info[kCGWindowName as String] as? String

            return WindowInfo(
                canonicalBounds: canonical,
                ownerName: ownerName,
                windowLayer: layer,
                ownerPID: pid,
                windowID: windowID,
                title: title
            )
        }
    }
}
