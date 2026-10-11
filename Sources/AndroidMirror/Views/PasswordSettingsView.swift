import SwiftUI
import AppKit

struct PasswordSettingsView: View {
    let store: MirrorStore
    @State private var selectedID = ""
    @State private var revealed: String?
    @State private var replacement = ""
    @State private var editing = false
    @State private var working = false
    @State private var message: String?
    @State private var expiry: Task<Void, Never>?
    @State private var ticket = UUID()
    @State private var privacyScope = PrivacyWindowScope()

    private var account: String? { store.registry.saved.first { $0.id == selectedID }?.id }
    var body: some View {
        @Bindable var preferences = store.preferences
        Form {
            Section(L10n.tr("Phone Unlock Password")) {
                if store.registry.saved.isEmpty {
                    Text(L10n.tr("Connect a phone to manage its password here.")).foregroundStyle(.secondary)
                } else {
                    Picker(L10n.tr("Devices"), selection: $selectedID) {
                        ForEach(store.registry.saved) { Text($0.name).tag($0.id) }
                    }.disabled(working)
                    Toggle(L10n.tr("Remember Password and Autofill"), isOn: Binding(
                        get: { account.map { store.credentials.contains($0) } ?? false },
                        set: { enabled in if enabled { edit() } else { remove() } }
                    )).disabled(working || store.credentials.busy)
                    Picker(L10n.tr("Password Input Method"), selection: $preferences.unlockInputMethod) {
                        ForEach(UnlockInputMethod.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(L10n.tr("Mac Authentication Validity"), selection: $preferences.authenticationMinutes) {
                        Text(L10n.tr("Every Time")).tag(Double(0))
                        ForEach([1, 5, 10, 15, 30], id: \.self) { Text(L10n.minutes($0)).tag(Double($0)) }
                    }
                    LabeledContent(L10n.tr("Saved Password")) {
                        Text(account.map { store.credentials.contains($0) } == true ? L10n.tr("Saved in Keychain") : L10n.tr("Not Saved"))
                            .foregroundStyle(.secondary)
                    }
                    if let revealed {
                        LabeledContent(L10n.tr("Password")) { Text(revealed).privacySensitive().font(.body.monospaced()) }
                        Button(L10n.tr("Hide Password")) { clear() }
                    }
                    if editing {
                        SecureField(L10n.tr("New Phone PIN or Password"), text: $replacement).privacySensitive()
                        HStack {
                            Button(L10n.tr("Save")) { save() }.disabled(replacement.isEmpty || working)
                            Button(L10n.tr("Cancel")) { clear() }.disabled(working)
                        }
                    } else {
                        HStack {
                            Button(L10n.tr("Show Password…")) { reveal() }
                                .disabled(account.map { !store.credentials.contains($0) } ?? true)
                            Button(account.map { store.credentials.contains($0) } == true ? L10n.tr("Change Password…") : L10n.tr("Save Password…")) { edit() }
                            Button(L10n.tr("Delete Password…"), role: .destructive) { remove() }
                                .disabled(account.map { !store.credentials.contains($0) } ?? true)
                        }.disabled(working || store.credentials.busy)
                    }
                    if working { ProgressView().controlSize(.small) }
                    if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                }
            }
            Section {
                Text(L10n.tr("Click Connect each time. macOS authenticates the first autofill; no further Mac authentication is needed within the validity period. Locking or sleeping your Mac, or quitting the app, requires fresh authentication. Passwords are encrypted in this Mac's Keychain."))
                Text(L10n.tr("Showing, changing or deleting passwords always requires Touch ID or your current Mac account's login password."))
                Text(L10n.tr("Changing a saved password does not change your phone's lock password. Revealed or edited content is hidden after 30 seconds, when the window loses focus, or when you leave Settings."))
            }.font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
        .background(PrivacyWindowAnchor(scope: privacyScope))
        .onAppear { selectedID = store.selectedRecord?.id ?? store.registry.saved.first?.id ?? "" }
        .onChange(of: selectedID) { _, _ in clear(); message = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in concealWhenUnfocused() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in concealWhenUnfocused() }
        .onDisappear { clear() }
        .onChange(of: preferences.authenticationMinutes) { _, _ in store.credentials.clearAutofill() }
    }
    private func concealWhenUnfocused() {
        if working { revealed = nil; replacement = ""; editing = false }
        else { clear() }
    }
    private func clear() {
        ticket = UUID(); revealed = nil; replacement = ""; editing = false
        expiry?.cancel(); expiry = nil
    }
    private func expire() {
        expiry?.cancel()
        expiry = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }; clear()
        }
    }
    private func run(_ operation: @escaping @MainActor (String, UUID) async throws -> Void) {
        guard let account, !working else { return }
        working = true; message = nil
        let id = ticket
        Task {
            defer { working = false }
            do { try await operation(account, id) }
            catch { if ticket == id, !MirrorStore.authenticationCancelled(error) { message = L10n.tr("Mac authentication or the Keychain operation was not completed. Try again.") } }
        }
    }
    private func reveal() {
        clear()
        run { account, id in
            let password = try await store.credentials.read(account)
            guard await awaitFocus(id) else { return }
            revealed = password; expire()
        }
    }
    private func edit() {
        clear()
        run { _, id in
            try await store.credentials.authorizeEditing()
            guard await awaitFocus(id) else { return }
            editing = true; expire()
        }
    }
    private func save() {
        let password = replacement
        run { account, id in
            try await store.credentials.save(password, account: account)
            guard ticket == id else { return }; clear(); message = L10n.tr("Saved password updated.")
        }
    }
    private func remove() {
        clear()
        run { account, id in
            try await store.credentials.remove(account)
            guard ticket == id else { return }; clear(); message = L10n.tr("Saved password deleted.")
        }
    }
    private func awaitFocus(_ id: UUID) async -> Bool {
        for _ in 0..<10 {
            guard ticket == id else { return false }
            if NSApp.isActive, privacyScope.window?.isKeyWindow == true { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
