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
                NSApplication.shared.orderFrontStandardAboutPanel(nil)
            }

            Divider()

            Button("Quit Cubit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            if appDelegate.settings.showMenuBarPercent,
               let percent = appDelegate.overlayController.appState.draftPercent {
                Text(percent)
            } else {
                Image(systemName: "ruler")
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: appDelegate.settings, hotkeyManager: appDelegate.hotkeyManager)
        }
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
