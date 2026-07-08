import AppKit
import SwiftUI

@MainActor
final class OnboardingWindow {
    private var window: NSWindow?
    private let permissions: PermissionsManager

    var onGranted: (() -> Void)?
    var onContinueWithout: (() -> Void)?

    init(permissions: PermissionsManager) {
        self.permissions = permissions
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let model = OnboardingModel(permissions: permissions)
        model.onGranted = { [weak self] in
            self?.close()
            self?.onGranted?()
        }
        model.onContinueWithout = { [weak self] in
            self?.close()
            self?.onContinueWithout?()
        }

        let hosting = NSHostingController(rootView: OnboardingView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = "Welcome to Cubit"
        // Normal level (not .floating): the system Screen Recording permission dialog is
        // presented above ordinary app windows but below floating ones, so a floating
        // onboarding window would sit on top of — and hide — the very prompt it triggers.
        // App activation below already brings this window forward on launch.
        window.level = .normal
        window.setContentSize(NSSize(width: 420, height: 360))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

@MainActor
@Observable
final class OnboardingModel {
    private let permissions: PermissionsManager
    var needsRelaunch = false

    var onGranted: (() -> Void)?
    var onContinueWithout: (() -> Void)?

    init(permissions: PermissionsManager) {
        self.permissions = permissions
    }

    var appIcon: NSImage { NSApp.applicationIconImage }

    func grant() {
        let requested = permissions.requestAccess()
        // A fresh grant frequently does not take effect until relaunch: request() may
        // report success while preflight still reads false, or vice-versa. When the two
        // disagree, or access still isn't live, surface the relaunch path.
        if requested && permissions.isGranted {
            onGranted?()
            return
        }
        // macOS only shows the capture prompt on the first-ever request per bundle id. Once
        // any decision exists (including a prior denial, or an entry re-added as "off" after a
        // reset), the request returns "not granted" with no dialog — so the button would appear
        // to do nothing. Send the user straight to the Screen Recording list to flip the toggle,
        // then relaunch to pick up the grant.
        permissions.openSystemSettings()
        needsRelaunch = true
    }

    func openSettings() {
        permissions.openSystemSettings()
        needsRelaunch = true
    }

    func relaunch() {
        permissions.relaunch()
    }

    func continueWithout() {
        onContinueWithout?()
    }
}

struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: model.appIcon)
                .resizable()
                .frame(width: 72, height: 72)

            Text("Cubit needs Screen Recording")
                .font(.headline)

            Text("Cubit captures a frozen snapshot of your screen so your measurements stay put while you draw, and so you can export a marked-up image. Nothing leaves your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button {
                    model.grant()
                } label: {
                    Label("Grant Screen Recording", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                if model.needsRelaunch {
                    Button {
                        model.relaunch()
                    } label: {
                        Label("Relaunch Cubit", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }

                Button {
                    model.openSettings()
                } label: {
                    Label("Open System Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }

                Button("Continue without capture") {
                    model.continueWithout()
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 420, height: 360)
    }
}
