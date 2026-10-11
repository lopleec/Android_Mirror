import SwiftUI

struct PairingView: View {
    let mirror: MirrorStore
    @State private var pairing = PairingStore()
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 22) {
            Text(pairing.paired ? L10n.tr("Connect Phone") : L10n.tr("Connect Android Phone")).font(.system(size: 20, weight: .semibold))
            if !pairing.paired {
                Picker(L10n.tr("Connection Method"), selection: $mode) {
                    Text(L10n.tr("QR Code")).tag(0)
                    Text(L10n.tr("Pairing Code")).tag(1)
                    Text(L10n.tr("Already Paired")).tag(2)
                }.labelsHidden().pickerStyle(.segmented).disabled(pairing.busy)
            }
            if pairing.paired || mode == 2 {
                connectFields
            } else if mode == 0 {
                qr
            } else {
                codeFields
            }
            if let error = pairing.error {
                Text(error).font(.callout).foregroundStyle(.white.opacity(0.85)).lineLimit(4).textSelection(.enabled)
                if ADBClient.executable == nil { Link(L10n.tr("Download Official Google ADB"), destination: ADBClient.downloadURL) }
            } else if pairing.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(pairing.message).font(.callout)
                }
            }
            Button(L10n.tr("Back")) { mirror.pairingPresented = false }
                .font(.system(size: 13)).buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).padding(.top, 4)
        }
        .padding(.horizontal, 28).frame(maxWidth: 350)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white).environment(\.colorScheme, .dark)
        .onAppear { pairing.startQR() }
        .onDisappear { pairing.cancelQR() }
        .onChange(of: mode) { _, value in
            pairing.error = nil; pairing.message = ""
            if value == 0 && !pairing.paired { pairing.startQR() } else { pairing.cancelQR() }
        }
        .onChange(of: pairing.connectedID) { _, id in
            guard let id else { return }
            mirror.pairingPresented = false
            Task { await mirror.connectPairedDevice(id) }
        }
    }
    private var qr: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.white)
                if let image = pairing.qrImage {
                    Image(nsImage: image).interpolation(.none).resizable().scaledToFit().padding(16)
                } else {
                    Button(L10n.tr("Refresh QR Code")) { pairing.startQR() }.buttonStyle(.bordered).tint(.gray)
                }
            }.frame(width: 218, height: 218).accessibilityLabel(L10n.tr("Wireless debugging pairing QR code"))
            Text(L10n.tr("Wireless debugging → Pair device with QR code"))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
        }
    }
    private var codeFields: some View {
        VStack(spacing: 12) {
            TextField(L10n.tr("Phone IP Address"), text: $pairing.host)
            TextField(L10n.tr("Pairing Port"), text: $pairing.pairPort)
            SecureField(L10n.tr("Six-Digit Pairing Code"), text: $pairing.code)
            PrimaryActionButton(title: L10n.tr("Connect"), disabled: !pairing.canPair) {
                Task { await pairing.pairWithCode() }
            }
        }.textFieldStyle(.roundedBorder).controlSize(.large).autocorrectionDisabled()
    }
    private var connectFields: some View {
        VStack(spacing: 12) {
            TextField(L10n.tr("Phone IP Address"), text: $pairing.host)
            TextField(L10n.tr("Connection Port"), text: $pairing.connectPort)
            PrimaryActionButton(title: L10n.tr("Connect"), disabled: !pairing.canConnect) {
                Task { await pairing.connectManually() }
            }
        }.textFieldStyle(.roundedBorder).controlSize(.large).autocorrectionDisabled()
    }
}
