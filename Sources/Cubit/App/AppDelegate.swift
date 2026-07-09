import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let overlayController: OverlayController
    /// Registering the Carbon hotkey doesn't depend on app-launch completion, so this is
    /// built eagerly alongside `overlayController` rather than deferred to
    /// `applicationDidFinishLaunching`. Non-optional means the Settings scene (which reads
    /// this to build its Shortcuts tab) can never observe a not-yet-initialized state.
    let hotkeyManager: HotkeyManager

    /// Cap on a handoff document read from `path=`. Handoff docs are tiny; this stops a hostile
    /// `cubit://` opener from pointing the app at a huge file.
    private static let maxHandoffFileBytes = 4 * 1024 * 1024

    override init() {
        let overlayController = OverlayController(settings: settings)
        self.overlayController = overlayController
        self.hotkeyManager = HotkeyManager(controller: overlayController)
        super.init()
    }

    /// macOS delivers `cubit://` URLs here (the scheme is registered in Info.plist as
    /// CFBundleURLTypes). This is an EXTERNAL attack surface — any app or webpage can open a
    /// `cubit://` URL — so the handler is strictly read-only and non-destructive: it only parses a
    /// handoff document and draws EDITABLE shapes the user can dismiss with Escape. It never
    /// writes, captures, exports, or executes anything from the URL. A malformed URL, missing or
    /// oversized file, or invalid document is a silent no-op (logged to stderr), never a crash.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleHandoffURL(url)
        }
    }

    private func handleHandoffURL(_ url: URL) {
        do {
            let payload = try HandoffURL.parse(url.absoluteString)
            let data: Data
            switch payload {
            case .inline(let inlineData):
                data = inlineData
            case .path(let path):
                data = try readHandoffFile(path)
            }
            let document = try JSONDecoder().decode(HandoffDocument.self, from: data)
            let measurements = try HandoffMapper.measurements(from: document)
            overlayController.handleHandoff(measurements, note: document.note)
        } catch {
            logIgnored(url, error)
        }
    }

    /// Reads (only) the handoff document at `path`. The path is followed solely to read + parse as
    /// JSON — never to write or execute. Over-sized or unreadable files throw, becoming a no-op.
    private func readHandoffFile(_ path: String) throws -> Data {
        let fileURL = URL(fileURLWithPath: path)
        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > Self.maxHandoffFileBytes {
            throw HandoffFileError.tooLarge(size)
        }
        return try Data(contentsOf: fileURL)
    }

    private enum HandoffFileError: Error { case tooLarge(Int) }

    private func logIgnored(_ url: URL, _ error: Error) {
        FileHandle.standardError.write(Data("Cubit: ignoring handoff URL (\(url.scheme ?? "?")://…): \(error)\n".utf8))
    }
}
