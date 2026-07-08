import AppKit
import UniformTypeIdentifiers

/// Delivers rendered PNG data to the outside world: a save panel, the clipboard, or a
/// drag-out item provider. Save/clipboard are the primary paths; drag rides SwiftUI's
/// `.onDrag` via `dragItemProvider`.
@MainActor
enum Exporter {
    static func defaultFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Cubit measurement \(formatter.string(from: date)).png"
    }

    /// Presents a save panel above the overlay windows and writes the PNG on confirm.
    /// Returns the written URL, or nil if cancelled or the write failed.
    @discardableResult
    static func saveToFile(_ data: Data, above overlayWindows: [NSWindow]) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFilename()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.level = panelLevel(above: overlayWindows)

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// A level strictly above the frontmost overlay window so the panel isn't buried.
    static func panelLevel(above overlayWindows: [NSWindow]) -> NSWindow.Level {
        let overlayTop = overlayWindows.map(\.level.rawValue).max()
            ?? Int(CGWindowLevelForKey(.maximumWindow))
        return NSWindow.Level(rawValue: overlayTop + 1)
    }

    static func copyToPasteboard(_ data: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        if let tiff = NSBitmapImageRep(data: data)?.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// An item provider that drops a PNG file into Finder or other apps.
    static func dragItemProvider(_ data: Data, filename: String? = nil) -> NSItemProvider {
        let filename = filename ?? defaultFilename()
        let provider = NSItemProvider()
        provider.suggestedName = filename
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            do {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try data.write(to: url)
                completion(url, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }

    /// Home-relative display path (`~/Desktop/…`) — never emits an absolute `/Users` path.
    static func abbreviatedPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
