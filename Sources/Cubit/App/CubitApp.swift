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

            SettingsLink {
                Text("Settings…")
            }
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
            if let hotkeyManager = appDelegate.hotkeyManager {
                SettingsView(settings: appDelegate.settings, hotkeyManager: hotkeyManager)
            } else {
                EmptyView()
            }
        }
    }
}
