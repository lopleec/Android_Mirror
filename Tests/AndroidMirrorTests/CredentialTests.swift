import XCTest
import LocalAuthentication
import CryptoKit
import Security
import AppKit
@testable import AndroidMirror

final class CredentialTests: XCTestCase {
    @MainActor func testValidMacAuthorizationStillRequiresExplicitConnectionClick() async throws {
        let backend = FakeCredentialBackend(), auth = FakeOwnerAuthentication(), clock = CredentialClock()
        let credentials = PhoneCredentialStore(backend: backend, authenticator: auth, uptime: { clock.now })
        _ = try await credentials.readForAutofill("phone-a", validity: 600)
        let name = "com.lopleec.androidmirror.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let record = SavedDevice(id: "phone-a", name: "Test phone", transportID: "test-transport")
        defaults.set(try JSONEncoder().encode([record]), forKey: "savedDevices")
        let store = MirrorStore(preferences: MirrorPreferences(defaults: defaults),
                                registry: DeviceRegistry(defaults: defaults), credentials: credentials)
        store.selectedID = record.id; store.phase = .connected
        for _ in 0..<3 {
            store.handleLockState(.locked)
            XCTAssertFalse(store.authenticating, "Lock discovery must not trigger cached autofill")
            XCTAssertFalse(store.unlockSending)
        }
        XCTAssertTrue(credentials.canAutofill(record.id, validity: 600))
        store.useSavedPassword() // The connection button explicitly invokes this action.
        XCTAssertTrue(store.authenticating)
        for _ in 0..<40 where store.authenticating { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(store.authenticating)
        XCTAssertEqual(auth.calls, 1, "Within 10 minutes the click must reuse the Mac verification")
        XCTAssertEqual(backend.operations, ["read"])
        store.disconnect()
    }
    @MainActor func testAutofillAuthorizationExpiresWithoutSlidingAndSettingsAlwaysReauthenticate() async throws {
        let backend = FakeCredentialBackend(), auth = FakeOwnerAuthentication(), clock = CredentialClock()
        let store = PhoneCredentialStore(backend: backend, authenticator: auth, uptime: { clock.now })
        let first = try await store.readForAutofill("phone-a", validity: 600)
        XCTAssertEqual(first, "original-password")
        clock.now = 599
        _ = try await store.readForAutofill("phone-a", validity: 600)
        XCTAssertEqual(auth.calls, 1)
        XCTAssertFalse(store.canAutofill("phone-b", validity: 600))
        _ = try await store.read("phone-a")
        XCTAssertEqual(auth.calls, 2) // Settings reveal never uses cached authorization.
        clock.now = 600
        XCTAssertFalse(store.canAutofill("phone-a", validity: 600))
        _ = try await store.readForAutofill("phone-a", validity: 600)
        XCTAssertEqual(auth.calls, 3)
        store.clearAutofill()
        XCTAssertFalse(store.canAutofill("phone-a", validity: 600))
        _ = try await store.readForAutofill("phone-a", validity: 0)
        XCTAssertFalse(store.canAutofill("phone-a", validity: 600))
        XCTAssertEqual(auth.calls, 4)
    }
    @MainActor func testPasswordReplacementAndMacSessionLockInvalidateAutofill() async throws {
        let backend = FakeCredentialBackend(), auth = FakeOwnerAuthentication()
        let store = PhoneCredentialStore(backend: backend, authenticator: auth)
        _ = try await store.readForAutofill("phone-a", validity: 600)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        XCTAssertFalse(store.canAutofill("phone-a", validity: 600))
        _ = try await store.readForAutofill("phone-a", validity: 600)
        try await store.save("changed", account: "phone-a")
        XCTAssertFalse(store.canAutofill("phone-a", validity: 600))
        let changed = try await store.readForAutofill("phone-a", validity: 600)
        XCTAssertEqual(changed, "changed")
        try await store.remove("phone-a")
        XCTAssertFalse(store.canAutofill("phone-a", validity: 600))
    }
    @MainActor func testCancelledAuthenticationDoesNotReadReplaceOrDeleteSecrets() async throws {
        let backend = FakeCredentialBackend()
        let auth = FakeOwnerAuthentication(); auth.cancel = true
        let store = PhoneCredentialStore(backend: backend, authenticator: auth)
        for operation in [0, 1, 2] {
            do {
                switch operation {
                case 0: _ = try await store.read("phone-a")
                case 1: try await store.save("new-password", account: "phone-a")
                default: try await store.remove("phone-a")
                }
                XCTFail("Cancelled system authentication must stop the operation")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        XCTAssertEqual(backend.operations, [])
        XCTAssertEqual(backend.passwords["phone-a"], "original-password")
        XCTAssertTrue(store.contains("phone-a")); XCTAssertFalse(store.busy)
    }
    @MainActor func testEveryReadAndPasswordManagementActionAuthenticatesFreshly() async throws {
        let backend = FakeCredentialBackend(), auth = FakeOwnerAuthentication()
        let store = PhoneCredentialStore(backend: backend, authenticator: auth)
        _ = try await store.read("phone-a"); _ = try await store.read("phone-a")
        try await store.authorizeEditing()
        try await store.save("new-password", account: "phone-a")
        try await store.remove("phone-a")
        XCTAssertEqual(auth.calls, 5)
        XCTAssertEqual(backend.operations, ["read", "read", "write", "delete"])
        XCTAssertFalse(store.contains("phone-a"))
    }
    @MainActor func testFailedReplacementKeepsOriginalAndUnsupportedPasswordNeverAuthenticates() async throws {
        let backend = FakeCredentialBackend(), auth = FakeOwnerAuthentication()
        let store = PhoneCredentialStore(backend: backend, authenticator: auth)
        backend.failWrite = true
        do { try await store.save("replacement", account: "phone-a"); XCTFail() } catch { }
        XCTAssertEqual(backend.passwords["phone-a"], "original-password")
        XCTAssertTrue(store.contains("phone-a"))
        do { try await store.save("密码", account: "phone-a"); XCTFail() } catch { }
        XCTAssertEqual(auth.calls, 1)
    }
    func testEncryptedEnvelopeRoundTripBindsDeviceAndRejectsTampering() throws {
        let enclaveStandIn = P256.KeyAgreement.PrivateKey(), peer = P256.KeyAgreement.PrivateKey()
        let secret = try enclaveStandIn.sharedSecretFromKeyAgreement(with: peer.publicKey)
        let reciprocal = try peer.sharedSecretFromKeyAgreement(with: enclaveStandIn.publicKey)
        let envelope = try EncryptedPhoneCredential.seal("private-password-123", secret: secret, account: "phone-a",
                                                        wrappedKey: Data([1,2,3]), peerKey: peer.publicKey.x963Representation)
        let encoded = try JSONEncoder().encode(envelope)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("private-password-123"))
        let decoded = try JSONDecoder().decode(EncryptedPhoneCredential.self, from: encoded)
        XCTAssertEqual(try decoded.open(secret: reciprocal, account: "phone-a"), "private-password-123")
        XCTAssertThrowsError(try decoded.open(secret: reciprocal, account: "phone-b"))
        var corrupted = decoded.ciphertext; corrupted[corrupted.count - 1] ^= 1
        let tampered = EncryptedPhoneCredential(version: 1, wrappedKey: decoded.wrappedKey, peerKey: decoded.peerKey, ciphertext: corrupted)
        XCTAssertThrowsError(try tampered.open(secret: reciprocal, account: "phone-a"))
    }
    func testSecureEnclaveRejectsUnauthenticatedUseWithoutDisplayingPrompt() throws {
        guard SecureEnclave.isAvailable else { throw XCTSkip("Secure Enclave unavailable on this test host") }
        let context = LAContext(); context.interactionNotAllowed = true
        defer { context.invalidate() }
        let protection = try XCTUnwrap(SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                                      [.privateKeyUsage, .userPresence], nil))
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: protection, authenticationContext: context)
        let restored = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: key.dataRepresentation, authenticationContext: context)
        XCTAssertThrowsError(try restored.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PrivateKey().publicKey))
    }
}
private final class CredentialClock: @unchecked Sendable { var now: TimeInterval = 0 }
private final class FakeOwnerAuthentication: OwnerAuthenticating, @unchecked Sendable {
    var calls = 0, cancel = false
    func authenticate(reason: String) async throws -> LAContext {
        calls += 1
        if cancel { throw CancellationError() }
        return LAContext()
    }
}
private final class FakeCredentialBackend: CredentialBackend, @unchecked Sendable {
    var passwords = ["phone-a": "original-password"]
    var operations: [String] = [], failWrite = false
    func accounts() throws -> Set<String> { Set(passwords.keys) }
    func read(account: String, context: LAContext) throws -> String { operations.append("read"); return passwords[account]! }
    func write(_ password: String, account: String, context: LAContext) throws {
        if failWrite { throw MirrorError.message("test write failed") }
        operations.append("write"); passwords[account] = password
    }
    func delete(account: String, context: LAContext) throws { operations.append("delete"); passwords.removeValue(forKey: account) }
}
