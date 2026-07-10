import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The app's Settings window: General, Shortcuts, Appearance, Export. Standard macOS
/// settings sizing — fixed width, height driven by content.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var hotkeyManager: HotkeyManager

    @State private var recordedKeyCode: UInt32
    @State private var recordedModifiers: UInt32

    init(settings: SettingsStore, hotkeyManager: HotkeyManager) {
        self.settings = settings
        self.hotkeyManager = hotkeyManager
        _recordedKeyCode = State(initialValue: hotkeyManager.keyCode)
        _recordedModifiers = State(initialValue: hotkeyManager.carbonModifiers)
    }

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            ShortcutsSettingsTab(
                hotkeyManager: hotkeyManager,
                keyCode: $recordedKeyCode,
                carbonModifiers: $recordedModifiers
            )
            .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            AppearanceSettingsTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            ExportSettingsTab(settings: settings)
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                if let failure = settings.launchAtLoginFailure {
                    FailureNote(
                        message: Text("Couldn’t change the login item. \(failure)"),
                        actionTitle: "Open Login Items Settings",
                        action: openLoginItemsSettings
                    )
                }
                Toggle("Show Percent in Menu Bar", isOn: $settings.showMenuBarPercent)
            }
            Section("Defaults") {
                Picker("Default Tool", selection: $settings.defaultTool) {
                    Text("Rectangle").tag(MeasurementKind.rectangle)
                    Text("Horizontal").tag(MeasurementKind.horizontal)
                    Text("Vertical").tag(MeasurementKind.vertical)
                }
                Picker("Default Reference", selection: $settings.defaultReferenceMode) {
                    Text("Window Under Cursor").tag(ReferenceMode.windowUnderCursor)
                    Text("Screen").tag(ReferenceMode.screen)
                    Text("Custom").tag(ReferenceMode.custom)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 16)
        .scrollDisabled(true)
        // The login item can be flipped in System Settings while Cubit runs; re-read it rather
        // than trusting the value cached at launch.
        .onAppear { settings.refreshLaunchAtLogin() }
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Inline, non-modal failure note: what went wrong, and the one button that fixes it.
///
/// Takes `Text`, not `String`: a `String` passed to `Text` opts out of localization entirely,
/// which is the quietest way to lose a translation.
private struct FailureNote: View {
    let message: Text
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                message
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                }
            }
        }
    }
}

private struct ShortcutsSettingsTab: View {
    var hotkeyManager: HotkeyManager
    @Binding var keyCode: UInt32
    @Binding var carbonModifiers: UInt32

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Toggle Measure")
                    Spacer()
                    ShortcutRecorderView(keyCode: $keyCode, carbonModifiers: $carbonModifiers) { newKeyCode, newModifiers in
                        hotkeyManager.rebind(keyCode: newKeyCode, carbonModifiers: newModifiers)
                    }
                    .frame(width: 160, height: 24)
                }

                if hotkeyManager.registrationFailed {
                    FailureNote(
                        message: Text("macOS refused this shortcut — another app is probably already using it. Pick a different combination.")
                    )
                }

                Button("Reset to Default") {
                    hotkeyManager.resetToDefault()
                    keyCode = HotkeyManager.defaultKeyCode
                    carbonModifiers = HotkeyManager.defaultModifiers
                }
            } footer: {
                Text("Click the shortcut field, then type a new combination. Esc cancels. Must include ⌘, ⌥, or ⌃.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 16)
        .scrollDisabled(true)
    }
}

private struct AppearanceSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Dim") {
                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: $settings.dimOpacity, in: SettingsStore.dimOpacityRange)
                        .accessibilityLabel("Dim")
                        .accessibilityValue(percentString(settings.dimOpacity))
                    HStack {
                        Text("\(Int((settings.dimOpacity * 100).rounded()))% dim")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.black.opacity(settings.dimOpacity))
                            .frame(width: 60, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(.separator)
                            )
                            .accessibilityHidden(true)
                    }
                    // The caption already carries the value the slider announces.
                    .accessibilityHidden(true)
                }
            }

            Section("Palette") {
                HStack(spacing: 8) {
                    ForEach(0..<Palette.colors.count, id: \.self) { index in
                        Circle()
                            .fill(Color(Palette.color(forIndex: index).nsColor))
                            .frame(width: 20, height: 20)
                    }
                }
                // Eight non-interactive swatches: one element naming the palette beats eight
                // anonymous images.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Measurement palette")
                .accessibilityValue((0..<Palette.colors.count).map { Palette.displayName(forIndex: $0) }.joined(separator: ", "))
            }

            Section("Markup") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Border width")
                        Spacer()
                        Text("\(Int(settings.measurementBorderWidth.rounded()))pt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.measurementBorderWidth, in: SettingsStore.measurementBorderWidthRange, step: 1)
                        .accessibilityLabel("Border width")
                        .accessibilityValue("\(Int(settings.measurementBorderWidth.rounded())) points")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Fill opacity")
                        Spacer()
                        Text("\(Int((settings.measurementFillOpacity * 100).rounded()))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.measurementFillOpacity, in: SettingsStore.measurementFillOpacityRange)
                        .accessibilityLabel("Fill opacity")
                        .accessibilityValue(percentString(settings.measurementFillOpacity))
                }

                Toggle("Show Label Pills", isOn: $settings.showLabelPills)

                Picker("Label Text Size", selection: $settings.labelTextSize) {
                    ForEach(LabelTextSize.allCases, id: \.self) { size in
                        // "S"/"M"/"L" is a legible control and an unintelligible announcement.
                        Text(verbatim: size.displayName)
                            // The control shows "S/M/L"; VoiceOver says the word, translated.
                            .accessibilityLabel(LocalizedStringKey(size.accessibilityName))
                            .tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 16)
        .scrollDisabled(true)
    }

    private func percentString(_ value: Double) -> String {
        localizedFormat(
            "a11y.settings.percentValue", "%@ percent",
            "Spoken value of a percentage slider; %@ is the number",
            LocalizedNumber.count(Int((value * 100).rounded()), locale: .current)
        )
    }
}

private struct ExportSettingsTab: View {
    @Bindable var settings: SettingsStore
    @State private var isChoosingFolder = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default save location")
                        // A chosen path renders verbatim; the fallback is UI text and must translate.
                        Group {
                            if let path = settings.defaultExportFolderDisplayPath {
                                Text(path)
                            } else {
                                Text("System Default")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose…") { isChoosingFolder = true }
                    if settings.defaultExportFolderPath != nil {
                        Button("Reset") { settings.defaultExportFolderPath = nil }
                    }
                }
                .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result {
                        settings.defaultExportFolderPath = url.path
                    }
                }

                Toggle("Copy to clipboard after export", isOn: $settings.copyAfterExport)
                Toggle("Write JSON sidecar", isOn: $settings.writeJSONSidecar)
            } footer: {
                Text("The sidecar is a .json file saved next to the image with the measurement data for tools to parse.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Include surrounding context", isOn: $settings.includeContext)
                Toggle("Window shadow", isOn: $settings.windowShadow)
                Picker("Background", selection: $settings.exportBackground) {
                    ForEach(ExportBackgroundStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .disabled(!settings.windowShadow || settings.includeContext)
            } header: {
                Text("Layout")
            } footer: {
                Text(settings.includeContext || !settings.windowShadow
                    ? "Background is off: it needs a styled window export (window shadow on, surrounding context off)."
                    : "The background fills the margins around styled window exports — a studio sweep, a gradient, or a classic Mac OS desktop. With a background on, the measurements panel moves below the window.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Machine name", isOn: $settings.imprintMachineName)
                Toggle("Window title", isOn: $settings.imprintWindowTitle)
                Toggle("App name", isOn: $settings.imprintAppName)
            } header: {
                Text("Metadata Imprints")
            } footer: {
                Text("Imprints are off by default; nothing is collected unless enabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 16)
        .scrollDisabled(true)
    }
}
