import Foundation
import Security
import LocalAuthentication
import Observation
import CryptoKit
import AppKit

protocol OwnerAuthenticating: Sendable {
    func authenticate(reason: String) async throws -> LAContext
}

struct MacOwnerAuthenticator: OwnerAuthenticating {
    func authenticate(reason: String) async throws -> LAContext {
        let context = LAContext()
        context.localizedCancelTitle = L10n.tr("Cancel")
        // Never silently reuse a previous biometric confirmation.
        context.touchIDAuthenticationAllowableReuseDuration = 0
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
                throw CancellationError()
            }
            try Task.checkCancellation()
            return context
        } catch { context.invalidate(); throw error }
    }
}

protocol CredentialBackend: Sendable {
    func accounts() throws -> Set<String>
    func read(account: String, context: LAContext) throws -> String
    func write(_ password: String, account: String, context: LAContext) throws
    func delete(account: String, context: LAContext) throws
}

/// Store only an encrypted envelope in the login Keychain. Its decryption key stays in the
/// Secure Enclave with native userPresence protection, including in an ad-hoc signed build.
/// No plaintext or unprotected software-key fallback is persisted.
struct KeychainCredentialBackend: CredentialBackend {
    static let service = "com.lopleec.androidmirror.sealed-phone-passwords"
    private func query(_ account: String? = nil) -> [String: Any] {
        var result: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: Self.service]
        if let account { result[kSecAttrAccount as String] = account }
        return result
    }
    func accounts() throws -> Set<String> {
        var request = query()
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitAll
        let context = LAContext(); context.interactionNotAllowed = true
        defer { context.invalidate() }
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        return Set((result as? [[String: Any]] ?? []).compactMap { $0[kSecAttrAccount as String] as? String })
    }
    func read(account: String, context: LAContext) throws -> String {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        try check(SecItemCopyMatching(request as CFDictionary, &result))
        guard let data = result as? Data else { throw MirrorError.message(L10n.tr("Could not read the saved phone password.")) }
        let envelope = try JSONDecoder().decode(EncryptedPhoneCredential.self, from: data)
        guard envelope.version == 1 else { throw MirrorError.message(L10n.tr("The saved password format is not supported.")) }
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: envelope.wrappedKey,
                                                               authenticationContext: context)
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: envelope.peerKey)
        let secret = try key.sharedSecretFromKeyAgreement(with: peer)
        return try envelope.open(secret: secret, account: account)
    }
    func write(_ password: String, account: String, context: LAContext) throws {
        guard SecureEnclave.isAvailable else {
            throw MirrorError.message(L10n.tr("Secure Enclave is unavailable on this Mac. Passwords cannot be saved securely; manual unlocking is still available."))
        }
        guard let protection = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                              [.privateKeyUsage, .userPresence], nil) else {
            throw MirrorError.message(L10n.tr("Could not create system password protection."))
        }
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: protection, authenticationContext: context)
        let peer = P256.KeyAgreement.PrivateKey()
        let secret = try key.sharedSecretFromKeyAgreement(with: peer.publicKey)
        let envelope = try EncryptedPhoneCredential.seal(password, secret: secret, account: account,
                                                        wrappedKey: key.dataRepresentation,
                                                        peerKey: peer.publicKey.x963Representation)
        let encrypted = try JSONEncoder().encode(envelope)
        var request = query(account)
        request[kSecUseAuthenticationContext as String] = context
        request[kSecValueData as String] = encrypted
        let status = SecItemAdd(request as CFDictionary, nil)
        if status == errSecDuplicateItem {
            var existing = query(account)
            existing[kSecUseAuthenticationContext as String] = context
            // Atomic replacement: cancellation preserves the existing encrypted credential.
            try check(SecItemUpdate(existing as CFDictionary, [kSecValueData as String: encrypted] as CFDictionary))
        } else { try check(status) }
    }

    func delete(account: String, context: LAContext) throws {
        var request = query(account)
        request[kSecUseAuthenticationContext as String] = context
        let status = SecItemDelete(request as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw MirrorError.message(L10n.format("Keychain operation failed (%d). Try Mac authentication again.", status))
        }
    }
}

@MainActor @Observable
final class PhoneCredentialStore {
    private(set) var accounts: Set<String>
    private(set) var busy = false
    private let backend: any CredentialBackend
    private let authenticator: any OwnerAuthenticating
    @ObservationIgnored private var autofill: [String: (password: String, verifiedAt: TimeInterval)] = [:]
    @ObservationIgnored private var autofillExpiry: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var authorizationEpoch = UUID()
    private let uptime: @Sendable () -> TimeInterval
    init(backend: any CredentialBackend = KeychainCredentialBackend(), authenticator: any OwnerAuthenticating = MacOwnerAuthenticator(), uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.backend = backend; self.authenticator = authenticator
        self.uptime = uptime
        accounts = (try? backend.accounts()) ?? []
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Delivered on the main queue; discard immediately when the Mac session closes.
                MainActor.assumeIsolated { self?.clearAutofill() }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearAutofill() }
        })
    }
    deinit {
        autofillExpiry?.cancel()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
    func contains(_ account: String?) -> Bool { account.map(accounts.contains) ?? false }
    func canAutofill(_ account: String?, validity: TimeInterval) -> Bool {
        guard validity > 0, let account, contains(account), let cached = autofill[account] else { return false }
        return uptime() - cached.verifiedAt < min(1800, validity)
    }
    /// Reuse only in this process, for this physical phone, within the user's explicit duration.
    /// Keychain protection stays intact; settings reads always authenticate independently.
    func readForAutofill(_ account: String, validity: TimeInterval) async throws -> String {
        if canAutofill(account, validity: validity), let cached = autofill[account] { return cached.password }
        autofill.removeValue(forKey: account)
        let epoch = authorizationEpoch
        let password = try await read(account)
        guard epoch == authorizationEpoch else { throw CancellationError() }
        if validity > 0 {
            autofill = [account: (password, uptime())]
            autofillExpiry?.cancel()
            autofillExpiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(min(1800, validity)))
                guard !Task.isCancelled else { return }; self?.clearAutofill()
            }
        }
        return password
    }
    func clearAutofill() {
        authorizationEpoch = UUID(); autofill.removeAll()
        autofillExpiry?.cancel(); autofillExpiry = nil
    }
    func read(_ account: String) async throws -> String {
        try await perform(reason: L10n.tr("Use the saved phone password to unlock Android Mirror")) { backend, context in
            try backend.read(account: account, context: context)
        }
    }
    func save(_ password: String, account: String) async throws {
        guard UnlockKeyboard.supports(password), !account.isEmpty else { throw MirrorError.message(L10n.tr("This phone password format is not supported.")) }
        clearAutofill()
        try await perform(reason: L10n.tr("Save or change the Android phone unlock password")) { backend, context in
            try backend.write(password, account: account, context: context)
        }
        accounts.insert(account)
    }
    func remove(_ account: String) async throws {
        clearAutofill()
        try await perform(reason: L10n.tr("Delete the saved Android phone password")) { backend, context in
            try backend.delete(account: account, context: context)
        }
        accounts.remove(account)
    }
    func authorizeEditing() async throws {
        try await perform(reason: L10n.tr("Manage Android phone unlock passwords")) { _, _ in () }
    }
    private func perform<T: Sendable>(reason: String, operation: @escaping @Sendable (any CredentialBackend, LAContext) throws -> T) async throws -> T {
        guard !busy else { throw MirrorError.message(L10n.tr("Complete the current Mac authentication first.")) }
        busy = true; defer { busy = false }
        let context = try await authenticator.authenticate(reason: reason)
        defer { context.invalidate() }
        try Task.checkCancellation()
        let backend = backend
        return try await Task.detached { try Task.checkCancellation(); return try operation(backend, context) }.value
    }
}

struct EncryptedPhoneCredential: Codable {
    let version: Int
    let wrappedKey: Data // Secure Enclave's device-bound opaque representation, never the private key.
    let peerKey: Data // Public P-256 key.
    let ciphertext: Data
    private static func associatedData(_ account: String) -> Data {
        Data((KeychainCredentialBackend.service + ":" + account).utf8)
    }
    private static func encryptionKey(_ secret: SharedSecret, account: String) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: associatedData(account),
                                     sharedInfo: Data("phone-unlock-envelope-v1".utf8), outputByteCount: 32)
    }
    static func seal(_ password: String, secret: SharedSecret, account: String, wrappedKey: Data, peerKey: Data) throws -> Self {
        let box = try AES.GCM.seal(Data(password.utf8), using: encryptionKey(secret, account: account),
                                  authenticating: associatedData(account))
        guard let combined = box.combined else { throw MirrorError.message(L10n.tr("Could not encrypt the phone password.")) }
        return Self(version: 1, wrappedKey: wrappedKey, peerKey: peerKey, ciphertext: combined)
    }
    func open(secret: SharedSecret, account: String) throws -> String {
        let data = try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: Self.encryptionKey(secret, account: account),
                                    authenticating: Self.associatedData(account))
        guard let password = String(data: data, encoding: .utf8) else { throw MirrorError.message(L10n.tr("The saved phone password is damaged.")) }
        return password
    }
}
