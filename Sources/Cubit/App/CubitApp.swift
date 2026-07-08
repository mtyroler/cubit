import SwiftUI

@main
struct CubitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Cubit", systemImage: "ruler") {
            Button("Measure (coming soon)") {}
                .disabled(true)

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
