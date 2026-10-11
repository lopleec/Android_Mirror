import SwiftUI

/// Center selection independently of the native window controls and trailing menu.
struct MirrorTitleBar: View {
    @Bindable var store: MirrorStore
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WindowDragStrip()
                deviceMenu(maxWidth: max(40, geometry.size.width - 164)).padding(.horizontal, 82)
                HStack {
                    Spacer()
                    optionsMenu.frame(width: 24, height: 24)
                }.padding(.trailing, 12)
            }.frame(width: geometry.size.width, height: 36)
        }.frame(height: 36)
    }
    private func deviceMenu(maxWidth: CGFloat) -> some View {
        Menu {
            ForEach(store.registry.saved) { record in
                Button { store.selectDevice(record.id) } label: {
                    Label(record.name, systemImage: store.selectedRecord?.id == record.id ? "checkmark" : "smartphone")
                }
            }
            ForEach(store.devices.filter { store.registry.record(for: $0) == nil }) { device in
                Button { store.selectDevice(device.id) } label: {
                    Label(device.name, systemImage: store.selectedID == device.id ? "checkmark" : "smartphone")
                }.disabled(!device.ready)
            }
            Divider()
            Button(L10n.tr("Add Phone…")) { store.addPhone() }
            SettingsLink { Text(L10n.tr("Manage Devices…")) }
        } label: {
            HStack(spacing: 5) {
                Text(store.hasSelection ? store.deviceName : L10n.tr("Select Device")).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).frame(maxWidth: maxWidth)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(store.hasSelection ? store.deviceName : L10n.tr("Select Device"))
            .accessibilityLabel(L10n.tr("Select Device"))
            .disabled(store.authenticating || store.credentials.busy)
    }
    private var optionsMenu: some View {
        @Bindable var preferences = store.preferences
        return Menu {
            Button(L10n.tr("Connect Phone…")) { store.addPhone() }
            Button(L10n.tr("Refresh Devices")) { Task { await store.refresh() } }
            PhoneActionButton(action: .directMirror, store: store)
            Divider()
            Picker(L10n.tr("Interaction"), selection: $preferences.mode) {
                ForEach(InteractionMode.allCases) { Text($0.title).tag($0) }
            }
            Picker(L10n.tr("Audio Output"), selection: $preferences.audioOutput) {
                ForEach(AudioOutput.allCases) { Text($0.title).tag($0) }
            }
            PhoneActionButton(action: .wake, store: store)
            Divider()
            ForEach([PhoneAction.home, .recentApps, .notifications, .screenshot, .rotate, .unlock, .screenPower]) {
                PhoneActionButton(action: $0, store: store)
            }
            Divider()
            Toggle(L10n.tr("Keep Window on Top"), isOn: $preferences.alwaysOnTop)
            SettingsLink { Text(L10n.tr("Settings…")) }
            Divider()
            Button(L10n.tr("Disconnect")) { store.disconnect() }.disabled(store.phase == .idle)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden)
            .help(L10n.tr("Mirroring Options")).accessibilityLabel(L10n.tr("Mirroring Options"))
    }
}
