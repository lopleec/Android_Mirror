import SwiftUI
import AppKit

/// Home and connected lock screen share one entry. Phone credentials never become clipboard text.
struct CredentialEntryView: View {
    let store: MirrorStore
    let connecting: Bool
    @State private var password = ""
    @State private var manual = false
    @FocusState private var focused: Bool

    private var busy: Bool { store.authenticating || store.unlockSending || store.credentials.busy }
    private var verified: Bool { store.credentials.canAutofill(store.credentialAccount, validity: store.preferences.authenticationMinutes * 60) }
    private var usesSavedEntry: Bool { store.hasSavedPassword && !manual && !store.isUSBConnection }
    var body: some View {
        VStack(spacing: 20) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "lock.fill").font(.system(size: 58, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                if usesSavedEntry {
                    Image(systemName: "touchid").font(.system(size: 27)).foregroundStyle(.white.opacity(0.9))
                        .offset(x: 12, y: 6)
                }
            }.padding(.bottom, 2).accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(connecting ? L10n.tr("Android Mirror Is Locked") : L10n.tr("Phone Is Locked")).font(.system(size: 20, weight: .semibold))
                Text(usesSavedEntry ? (verified ? L10n.tr("Click Connect. No Mac authentication needed.") : L10n.tr("Connect with Touch ID or your Mac login password")) : L10n.tr("Enter your phone password to unlock"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                if store.isUSBConnection {
                    Text(L10n.tr("USB Connection")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
            }
            if usesSavedEntry {
                PrimaryActionButton(
                    title: busy ? (store.unlockSending ? L10n.tr("Unlocking…") : L10n.tr("Authenticating…")) : L10n.tr("Connect"),
                    symbol: verified ? "lock.open" : "touchid", disabled: busy,
                    action: store.useSavedPassword
                ).frame(width: MirrorLayout.credentialWidth)
                Button(L10n.tr("Use Phone Password")) { manual = true; focused = true }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).disabled(busy)
            } else {
                VStack(spacing: 12) {
                    SecureField(L10n.tr("Phone PIN or Password"), text: $password)
                        .textFieldStyle(.plain).focused($focused)
                        .padding(.horizontal, 10).frame(height: MirrorLayout.fieldHeight)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MirrorLayout.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: MirrorLayout.controlRadius).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                        .privacySensitive().disabled(busy).onSubmit(submit)
                    PrimaryActionButton(
                        title: store.unlockSending ? L10n.tr("Unlocking…") : (connecting ? (password.isEmpty ? L10n.tr("Connect") : L10n.tr("Connect and Unlock")) : L10n.tr("Unlock")),
                        disabled: (!connecting && password.isEmpty) || busy, action: submit
                    )

                }.frame(width: MirrorLayout.credentialWidth)

            }
            if let message = store.unlockMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center).frame(maxWidth: 270)
            }
        }
        .padding(24).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.selectedID) { _, _ in clear(); manual = false; focused = store.isUSBConnection }
        .onAppear { focused = store.isUSBConnection }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in clear() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in clear() }
        .onDisappear { clear() }
    }
    private func clear() { password = ""; focused = false }
    private func submit() {
        guard !busy else { return }
        if password.isEmpty, connecting { store.connect(); return }
        guard !password.isEmpty else { return }
        store.connectWithPassword(password, method: store.preferences.unlockInputMethod)
        clear()
    }
}
