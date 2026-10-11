import SwiftUI
import AppKit

struct SettingsView: View {
    let store: MirrorStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var preferences = store.preferences
        TabView {
            Form {
                Section(L10n.tr("Interaction")) {
                    Picker(L10n.tr("Mode"), selection: $preferences.mode) {
                        ForEach(InteractionMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }.pickerStyle(.segmented)
                    if preferences.mode == .viewOnly {
                        Text(L10n.tr("View the screen while using your phone directly. Mac keyboard, mouse and clipboard sync are disabled."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(L10n.tr("Phone Screen")) {
                    Toggle(L10n.tr("Keep Awake While Controlling"), isOn: $preferences.keepAwake)
                    Toggle(L10n.tr("Turn Off Phone Screen While Controlling"), isOn: $preferences.autoScreenOff)
                    Text(L10n.tr("Extends the screen timeout after unlocking without repeated wake commands. Screen-off starts after unlocking; disconnecting restores the original timeout."))
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(!preferences.mode.allowsInput)
                Section(L10n.tr("Input and Window")) {
                    Picker(L10n.tr("Audio Output"), selection: $preferences.audioOutput) {
                        ForEach(AudioOutput.allCases) { output in Text(output.title).tag(output) }
                    }
                    Toggle(L10n.tr("Sync Text Clipboard"), isOn: $preferences.clipboardSync).disabled(!preferences.mode.allowsInput)
                    Toggle(L10n.tr("Keep Window on Top"), isOn: $preferences.alwaysOnTop)
                }
                Section(L10n.tr("Picture")) {
                    Picker(L10n.tr("Resolution"), selection: $preferences.maxSize) {
                        Text(L10n.tr("Smooth · 1280p")).tag(1280)
                        Text(L10n.tr("Detailed · 1920p")).tag(1920)
                        Text(L10n.tr("Original Resolution")).tag(0)
                    }
                    Picker(L10n.tr("Picture Quality"), selection: $preferences.videoQuality) {
                        ForEach(VideoQuality.allCases) { quality in Text(quality.title).tag(quality) }
                    }
                    Text(L10n.format("Video bit rate: %d Mbps", preferences.videoQuality.bitRate(maxSize: preferences.maxSize) / 1_000_000))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(L10n.tr("Higher quality reduces compression artifacts and uses more bandwidth. For fine detail, choose Original Resolution and USB. Changes reconnect the video stream."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label(L10n.tr("General"), systemImage: "slider.horizontal.3") }

            Form {
                Section(L10n.tr("My Devices")) {
                    if store.registry.saved.isEmpty {
                        Text(L10n.tr("Connected phones are saved here automatically."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.registry.saved) { device in
                        DeviceSettingsRow(store: store, device: device) {
                            store.selectDevice(device.id); dismiss()
                        }
                    }
                    Button(L10n.tr("Add Phone…")) { store.addPhone(); dismiss() }
                    Toggle(L10n.tr("Discover Saved Wireless Devices Automatically"), isOn: $preferences.autoReconnect)
                }
                DisclosureGroup(L10n.tr("Advanced Connection Settings")) {
                    Link(L10n.tr("Download ADB from Google (Platform-Tools)"), destination: ADBClient.downloadURL)
                    HStack {
                        Text(ADBClient.executable?.path ?? L10n.tr("ADB Not Found"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                        Spacer()
                        Button(L10n.tr("Choose ADB…")) {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url { preferences.adbPath = url.path }
                        }
                    }
                    if !preferences.adbPath.isEmpty { Button(L10n.tr("Use Automatic Selection")) { preferences.adbPath = "" } }
                }
            }.formStyle(.grouped).tabItem { Label(L10n.tr("Devices"), systemImage: "iphone.gen3.radiowaves.left.and.right") }
            PasswordSettingsView(store: store).tabItem { Label(L10n.tr("Password"), systemImage: "lock") }
        }.padding(10).frame(width: 490, height: 490)
    }
}
