import SwiftUI

struct WelcomeView: View {
    let store: MirrorStore
    var body: some View {
        if store.registry.saved.isEmpty {
            VStack(spacing: 22) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 54, weight: .ultraLight)).foregroundStyle(.white.opacity(0.85))
                VStack(spacing: 10) {
                    Text(L10n.tr("Android Mirror")).font(.system(size: 22, weight: .semibold))
                    Text(L10n.tr("Use your phone on your Mac")).font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                }
                PrimaryActionButton(title: L10n.tr("Connect Phone")) { store.addPhone() }
                    .frame(width: 162)
            }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.preferences.mode.allowsInput {
            CredentialEntryView(store: store, connecting: true)
        } else {
            VStack(spacing: 20) {
                Text(store.deviceName).font(.title2.bold())
                PrimaryActionButton(title: L10n.tr("Start Mirroring")) { store.connect() }
                    .frame(width: MirrorLayout.credentialWidth)
            }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ConnectionBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.015, green: 0.06, blue: 0.075)
                Ellipse().fill(Color(red: 0.18, green: 0.50, blue: 0.53))
                    .frame(width: geometry.size.width * 1.5, height: geometry.size.height * 0.6)
                    .rotationEffect(.degrees(-35)).offset(x: geometry.size.width * 0.22, y: -geometry.size.height * 0.2).blur(radius: 55)
                Ellipse().fill(Color(red: 0.5, green: 0.49, blue: 0.64).opacity(0.8))
                    .frame(width: geometry.size.width * 1.3, height: geometry.size.height * 0.32)
                    .rotationEffect(.degrees(-35)).offset(x: geometry.size.width * 0.12, y: -geometry.size.height * 0.37).blur(radius: 50)
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
    }
}
