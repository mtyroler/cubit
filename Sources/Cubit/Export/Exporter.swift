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
    /// `directoryURL`, when non-nil, pre-selects that folder; nil falls back to the system
    /// default (the panel's own last-used location). Returns the written URL, or nil if
    /// cancelled or the write failed.
    @discardableResult
    static func saveToFile(_ data: Data, above overlayWindows: [NSWindow], directoryURL: URL? = nil) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFilename()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.level = panelLevel(above: overlayWindows)
        if let directoryURL {
            panel.directoryURL = directoryURL
        }

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Resolves `SettingsStore.defaultExportFolderPath` to a directory URL for the save
    /// panel, falling back to nil (system default) when unset or the folder no longer
    /// exists. `isDirectory` is injectable so the fallback logic is testable without
    /// touching the real filesystem.
    nonisolated static func resolvedSaveDirectory(
        forPath path: String?,
        isDirectory: (String) -> Bool = { path in
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return exists && isDir.boolValue
        }
    ) -> URL? {
        guard let path, isDirectory(path) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
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

    /// An item provider that drops a PNG file into Finder or other apps. The PNG is rendered
    /// lazily when the drop is accepted (via the async `data` producer) so the drag can carry
    /// an occlusion-free window capture that isn't ready synchronously at drag start.
    static func dragItemProvider(
        filename: String? = nil,
        data: @escaping @Sendable @MainActor () async -> Data?
    ) -> NSItemProvider {
        let filename = filename ?? defaultFilename()
        let provider = NSItemProvider()
        provider.suggestedName = filename
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            Task {
                guard let payload = await data() else {
                    completion(nil, false, nil)
                    return
                }
                do {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    try payload.write(to: url)
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
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
