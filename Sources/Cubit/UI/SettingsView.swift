import SwiftUI

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
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Show percent in menu bar", isOn: $settings.showMenuBarPercent)
            }
            Section("Defaults") {
                Picker("Default tool", selection: $settings.defaultTool) {
                    Text("Rectangle").tag(MeasurementKind.rectangle)
                    Text("Horizontal").tag(MeasurementKind.horizontal)
                    Text("Vertical").tag(MeasurementKind.vertical)
                }
                Picker("Default reference", selection: $settings.defaultReferenceMode) {
                    Text("Window under cursor").tag(ReferenceMode.windowUnderCursor)
                    Text("Screen").tag(ReferenceMode.screen)
                    Text("Custom").tag(ReferenceMode.custom)
                }
            }
        }
        .formStyle(.grouped)
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
    }
}

private struct AppearanceSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Dim") {
                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: $settings.dimOpacity, in: SettingsStore.dimOpacityRange)
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
                    }
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
            }
        }
        .formStyle(.grouped)
    }
}

private struct ExportSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Copy to clipboard after export", isOn: $settings.copyAfterExport)
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
    }
}
