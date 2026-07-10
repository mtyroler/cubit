import SwiftUI

@main
struct CubitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button {
                appDelegate.overlayController.toggle()
            } label: {
                Label("Measure", systemImage: "ruler")
            }
            .keyboardShortcut("m", modifiers: [.control, .option, .command])

            Divider()

            SettingsMenuButton()
                .keyboardShortcut(",", modifiers: [.command])

            Button("About Cubit") {
                AboutPanel.show()
            }

            Divider()

            Button("Quit Cubit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            if appDelegate.settings.showMenuBarPercent,
               let percent = appDelegate.overlayController.appState.draftPercent {
                // Monospaced digits: the label is rewritten on every mouse-move during a drag,
                // and proportional digits shove every menu bar item to its left back and forth.
                Text(percent)
                    .monospacedDigit()
                    .accessibilityLabel("Cubit, measuring \(percent)")
            } else {
                Image(systemName: "ruler")
                    .accessibilityLabel("Cubit")
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: appDelegate.settings, hotkeyManager: appDelegate.hotkeyManager)
        }
    }
}

/// Shows the standard About panel for an `LSUIElement` (accessory) app. Two problems to solve:
/// `orderFrontStandardAboutPanel` alone opens the panel behind every other app (Cubit is never
/// frontmost by default), and — because the panel lives in Cubit's normal space — it never appears
/// over another app running full screen (a Zoom call, say), so it looks like nothing happened.
/// Activating surfaces it; giving the panel `.canJoinAllSpaces` lets it render in whatever space is
/// active, including a full-screen app's. The deferred block covers the menu dismissal re-deactivating
/// the app the instant the panel appears.
private enum AboutPanel {
    @MainActor
    static func show() {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            guard let panel = aboutPanel(newSince: before) else { return }
            // Persisted on the reused singleton, so later opens inherit it too.
            panel.collectionBehavior.insert(.canJoinAllSpaces)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// The about panel is a reused singleton: on first open it's the freshly-added window; on later
    /// opens it's the visible window titled for the app (title fallback for when the diff is empty).
    @MainActor
    private static func aboutPanel(newSince before: Set<ObjectIdentifier>) -> NSWindow? {
        if let fresh = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) }) {
            return fresh
        }
        return NSApp.windows.first { $0.isVisible && ($0.title == "About \(appName)" || $0.title == appName) }
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Cubit"
    }
}

/// `SettingsLink`/`openSettings` alone opens the Settings window but does not activate
/// the app. Cubit is `LSUIElement` (no Dock icon, never frontmost by default), so an
/// unactivated Settings window opens genuinely onscreen yet behind every other app —
/// indistinguishable from not opening at all. `openSettings()` builds the window
/// asynchronously, so activation has to be applied once the window actually exists, not
/// just fired alongside the call — a short poll covers the gap.
private struct SettingsMenuButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            openSettings()
            Self.activateSettingsWindow()
        }
    }

    private static func activateSettingsWindow(attempt: Int = 0) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: isSettingsWindow) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard attempt < 20 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            activateSettingsWindow(attempt: attempt + 1)
        }
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
            || window.title.hasSuffix("Settings")
    }
}
