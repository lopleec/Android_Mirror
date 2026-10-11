import SwiftUI

struct ContentView: View {
    @Bindable var store: MirrorStore

    var body: some View {
        @Bindable var preferences = store.preferences
        ZStack(alignment: .top) {
            ZStack {
                if store.phase == .idle {
                    ConnectionBackdrop()
                    if store.pairingPresented {
                        PairingView(mirror: store)
                    } else {
                        WelcomeView(store: store)
                    }
                } else {
                    Color.black
                    MirrorSurface(store: store).allowsHitTesting(store.acceptsPhoneInput)
                    if store.phoneLockState == .locked || store.unlockPresented {
                        UnlockView(store: store)
                    } else if store.phase == .starting || !store.hasVideo || store.phoneLockState == .unknown {
                        ConnectingView(store: store)
                    }
                }
                if let error = store.error, !store.pairingPresented {
                    VStack {
                        Spacer()
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error).font(.callout).lineLimit(4).textSelection(.enabled)
                                if ADBClient.executable == nil {
                                    Link(L10n.tr("Download Official Google ADB"), destination: ADBClient.downloadURL)
                                }
                            }
                            Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(L10n.tr("Dismiss Message"))
                        }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(20)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
            .padding(.horizontal, 6).padding(.bottom, 6).padding(.top, 36)

            MirrorTitleBar(store: store)
        }
        .frame(minWidth: 320, minHeight: store.connected && store.size.width > store.size.height ? 240 : 570)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowPreferences(alwaysOnTop: preferences.alwaysOnTop, videoSize: store.connected ? store.size : nil))
        .onChange(of: preferences.mode) { _, _ in store.configurationChanged() }
        .onChange(of: preferences.keepAwake) { _, _ in store.configurationChanged() }
        .onChange(of: preferences.autoScreenOff) { _, _ in store.autoScreenOffChanged() }
        .onChange(of: preferences.audioOutput) { _, _ in store.configurationChanged() }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}
