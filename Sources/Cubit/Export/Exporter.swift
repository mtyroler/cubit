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
    /// default (the panel's own last-used location). Returns the written URL, or nil if the
    /// user cancelled. A failed write raises an alert before returning nil — an export that
    /// silently does nothing is worse than one that fails loudly.
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

        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            presentWriteFailure(error, url: url, above: overlayWindows)
            return nil
        }
    }

    /// The export failed after the user chose a destination. Say so, name the destination, and
    /// carry the underlying reason — the disk being full or the volume read-only is actionable.
    private static func presentWriteFailure(_ error: Error, url: URL, above overlayWindows: [NSWindow]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t save “\(url.lastPathComponent)”."
        alert.informativeText = (error as NSError).localizedFailureReason
            ?? error.localizedDescription
        alert.addButton(withTitle: "OK")

        // The overlay sits at maximum window level; an alert beneath it would never be seen.
        alert.window.level = panelLevel(above: overlayWindows)
        NSApp.activate()
        alert.runModal()
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

    /// The JSON sidecar location for a saved PNG: same basename, `.json` extension.
    nonisolated static func sidecarURL(for imageURL: URL) -> URL {
        imageURL.deletingPathExtension().appendingPathExtension("json")
    }

    /// Writes the JSON sidecar next to a saved image. A failure here is swallowed on purpose:
    /// the image export already succeeded and must never be undone by a sidecar problem.
    /// Returns the written URL, or nil if encoding/writing failed.
    @discardableResult
    nonisolated static func writeSidecar(_ sidecar: MeasurementSidecar, besideImageAt imageURL: URL) -> URL? {
        let url = sidecarURL(for: imageURL)
        do {
            try sidecar.jsonData().write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
