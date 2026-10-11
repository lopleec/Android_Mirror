import SwiftUI

struct DeviceSettingsRow: View {
    let store: MirrorStore
    let device: SavedDevice
    let onSelect: () -> Void
    @State private var editing = false
    @State private var name = ""
    @State private var removing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(device.name, systemImage: "smartphone").lineLimit(1)
                Spacer()
                Button(L10n.tr("Select"), action: onSelect)
                Menu {
                    Button(L10n.tr("Edit Name…")) { name = device.name; editing = true }
                    Button(L10n.tr("Delete Device…"), role: .destructive) { removing = true }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            if editing {
                HStack {
                    TextField(L10n.tr("Device Name"), text: $name).onSubmit(rename)
                    Button(L10n.tr("Done"), action: rename).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(L10n.tr("Cancel")) { editing = false; name = "" }
                }
            }
        }
        .confirmationDialog(L10n.format("Delete “%@”?", device.name), isPresented: $removing) {
            Button(L10n.tr("Delete Device"), role: .destructive) { Task { await store.removeDevice(device) } }
        } message: { Text(L10n.tr("Removes the device record and saved password from this app. You can reuse the phone's Wireless debugging pairing when adding it again.")) }
    }
    private func rename() { store.registry.rename(device, to: name); editing = false; name = "" }
}
