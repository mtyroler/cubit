import AppKit
import SwiftUI

@MainActor
final class OnboardingWindow {
    private var window: NSWindow?
    private let permissions: PermissionsManager
    private var model: OnboardingModel?
    private var closeObserver: WindowCloseObserver?
    /// Set while `close()` is tearing the window down as part of granting or continuing-without, so
    /// the window-close notification isn't mistaken for the user dismissing the gate.
    private var isFinishing = false

    var onGranted: (() -> Void)?
    var onContinueWithout: (() -> Void)?
    /// The user closed the gate without granting and without continuing — a refusal.
    var onDismiss: (() -> Void)?

    /// How many measurements an agent is waiting to show, if the gate was triggered by a handoff.
    var pendingHandoffCount: Int? {
        didSet { model?.pendingHandoffCount = pendingHandoffCount }
    }

    init(permissions: PermissionsManager) {
        self.permissions = permissions
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if let window {
            model?.pendingHandoffCount = pendingHandoffCount
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let model = OnboardingModel(permissions: permissions)
        model.pendingHandoffCount = pendingHandoffCount
        model.onGranted = { [weak self] in
            self?.close()
            self?.onGranted?()
        }
        model.onContinueWithout = { [weak self] in
            self?.close()
            self?.onContinueWithout?()
        }
        self.model = model

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
        window.setContentSize(NSSize(width: 420, height: 470))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        // The window is `.closable`: clicking its close button must be treated as a refusal, not a
        // silent deferral. Without this, a proposal queued behind the gate stays queued and injects
        // at the NEXT overlay open — possibly hours later, over unrelated content.
        closeObserver = WindowCloseObserver(window: window) { [weak self] in
            guard let self, !self.isFinishing else { return }
            self.window = nil
            self.model = nil
            self.onDismiss?()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        isFinishing = true
        defer { isFinishing = false }
        window?.orderOut(nil)
        window = nil
        model = nil
        closeObserver = nil
    }
}

/// Reports the window's close button back to `OnboardingWindow`. A separate `NSObject` because
/// `NSWindow.delegate` requires one, and because `NSWindow.delegate` is a weak reference the owner
/// must hold this strongly.
@MainActor
private final class WindowCloseObserver: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(window: NSWindow, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

@MainActor
@Observable
final class OnboardingModel {
    private let permissions: PermissionsManager
    var needsRelaunch = false
    /// Non-nil when an agent's handoff is what triggered this gate.
    var pendingHandoffCount: Int?

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

    static func handoffPrompt(count: Int) -> String {
        let noun = count == 1 ? "1 measurement" : "\(count) measurements"
        let pronoun = count == 1 ? "it" : "them"
        return "An agent proposed \(noun). Grant access to see \(pronoun) on screen."
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: model.appIcon)
                .resizable()
                .frame(width: 72, height: 72)

            Text("Cubit needs Screen Recording")
                .font(.headline)

            if let count = model.pendingHandoffCount, count > 0 {
                Label(Self.handoffPrompt(count: count), systemImage: "sparkles")
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Cubit captures a frozen snapshot of your screen so your measurements stay put while you draw, and so you can export a marked-up image. Nothing leaves your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // macOS names this permission "Screen & System Audio Recording" and its prompt says
            // "record this computer's screen and audio". Cubit never captures audio; say so, because
            // the user cannot tell from the system's wording.
            Text("macOS calls this “Screen & System Audio Recording.” Cubit takes still snapshots only — it never records audio.")
                .font(.footnote)
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
        .frame(width: 420, height: 470)
    }
}
