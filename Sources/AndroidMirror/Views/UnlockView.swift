import SwiftUI

struct UnlockView: View {
    let store: MirrorStore
    var body: some View {
        ZStack {
            ConnectionBackdrop()
            if store.preferences.mode.allowsInput {
                CredentialEntryView(store: store, connecting: false)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "lock.fill").font(.system(size: 58)).foregroundStyle(.white.opacity(0.7))
                    Text(L10n.tr("Phone Is Locked")).font(.title3.bold())
                    Text(L10n.tr("Unlock on your phone")).font(.callout).foregroundStyle(.secondary)
                }.foregroundStyle(.white)
            }
        }
    }
}

struct ConnectingView: View {
    let store: MirrorStore
    var body: some View {
        ZStack {
            ConnectionBackdrop()
            VStack(spacing: 10) {
                Text(store.recoveringVideo ? L10n.tr("Restoring Screen") : L10n.tr("Connecting"))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                Text(store.deviceName).font(.system(size: 29, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9)).lineLimit(2).multilineTextAlignment(.center)
                ProgressView().controlSize(.small).tint(.white.opacity(0.65)).padding(.top, 20)
                Button(L10n.tr("Cancel")) { store.disconnect() }.buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4)).padding(.top, 12)
            }.padding(24)
        }
    }
}
