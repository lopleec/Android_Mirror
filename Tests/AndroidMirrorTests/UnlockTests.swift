import XCTest
@testable import AndroidMirror

final class UnlockTests: XCTestCase {
    func testPixelAndVendorKeyguardParsingDoesNotGuessFromOtherFlags() {
        XCTAssertEqual(PhoneLockState.parse("KeyguardServiceDelegate\n showing=true\n KeyguardStateMonitor\n mIsShowing=true\n"), .locked)
        XCTAssertEqual(PhoneLockState.parse("mKeyguardOccluded=false\n mIsShowing=false"), .unlocked)
        XCTAssertEqual(PhoneLockState.parse("keyguardShowing=true"), .locked)
        XCTAssertEqual(PhoneLockState.parse("mShowingLockscreen=false"), .unlocked)
        XCTAssertEqual(PhoneLockState.parse("deviceHasKeyguard=true\n mKeyguardOccluded=false"), .unknown)
        XCTAssertEqual(PhoneLockState.parse("mIsShowing=true\n mIsShowing=false"), .unknown)
    }
    func testUHIDFramesMatchDeviceProtocolAndReleaseEveryKey() throws {
        let create = UnlockKeyboard.create()
        XCTAssertEqual(create[0], 12)
        XCTAssertEqual(create.integer(at: 1, as: UInt16.self), 1)
        let nameLength = Int(create[7])
        XCTAssertEqual(create.integer(at: 8 + nameLength, as: UInt16.self), 63)
        XCTAssertEqual(Data(create.suffix(63)), UnlockKeyboard.descriptor)
        let packets = try XCTUnwrap(UnlockKeyboard.strokes(for: "A!0"))
        XCTAssertEqual(packets.count, 8)
        XCTAssertEqual(packets[0], Data([13, 0, 1, 0, 8, 2, 0, 4, 0, 0, 0, 0, 0]))
        XCTAssertEqual(packets[2][7], 0x1e)
        XCTAssertEqual(packets[2][5], 2)
        XCTAssertEqual(packets[4][7], 0x27)
        XCTAssertEqual(packets[6][7], 0x28) // Enter exactly once.
        for index in stride(from: 1, to: packets.count, by: 2) { XCTAssertEqual(packets[index], UnlockKeyboard.report()) }
        XCTAssertEqual(UnlockKeyboard.destroy(), Data([14, 0, 1]))
    }
    func testCredentialValidationNeverSendsPartialOrUnsupportedPassword() {
        for text in ["", "密码", "a\n", String(repeating: "1", count: 129)] {
            XCTAssertNil(UnlockKeyboard.strokes(for: text))
        }
        let ascii = String(bytes: Array(UInt8(32)...UInt8(126)), encoding: .ascii)!
        XCTAssertEqual(UnlockKeyboard.strokes(for: ascii)?.count, 192)
    }
    @MainActor func testControlDoesNotDependOnVideoAndUnlockCannotStartInViewOnly() {
        let name = "com.lopleec.androidmirror.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = MirrorPreferences(defaults: defaults)
        let store = MirrorStore(preferences: preferences)
        store.phase = .connected
        XCTAssertFalse(store.hasVideo)
        XCTAssertTrue(store.canControl)
        preferences.mode = .viewOnly
        store.prepareUnlock()
        XCTAssertFalse(store.unlockPresented)
    }
}
