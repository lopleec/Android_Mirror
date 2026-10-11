import SwiftUI
import AppKit

struct MirrorCommands: Commands {
    let store: MirrorStore
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu(L10n.tr("Phone")) {
            Button(L10n.tr("Add Wireless Device…")) { store.addPhone() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button(store.connected ? L10n.tr("Disconnect") : L10n.tr("Start Mirroring")) {
                if store.phase == .idle { store.connect() } else { store.disconnect() }
            }.keyboardShortcut("r")
            PhoneActionButton(action: .directMirror, store: store)
            Divider()
            ForEach([PhoneAction.home, .recentApps, .notifications, .back]) {
                PhoneActionButton(action: $0, store: store, includeShortcut: true)
            }
            Divider()
            ForEach([PhoneAction.screenshot, .rotate, .wake, .screenPower, .unlock]) {
                PhoneActionButton(action: $0, store: store, includeShortcut: true)
            }
        }
        CommandGroup(replacing: .help) {
            Button(L10n.tr("Connection and Keyboard Guide")) {
                if let guide = L10n.guideURL { NSWorkspace.shared.open(guide) }
            }
        }
    }
}
