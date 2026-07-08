import SwiftUI

@main
struct CubitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Cubit", systemImage: "ruler") {
            Button {
                appDelegate.overlayController.toggle()
            } label: {
                Label("Measure", systemImage: "ruler")
            }
            .keyboardShortcut("m", modifiers: [.option, .command])

            Divider()

            Button("About Cubit") {
                NSApplication.shared.orderFrontStandardAboutPanel(nil)
            }

            Button("Quit Cubit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            EmptyView()
        }
    }
}
