import XCTest
@testable import AndroidMirror

final class CompatibilityTests: XCTestCase {
    func testIPv6AndDNSRoundTripAndUnsafeAddressesRejected() {
        for (host, port, expected) in [
            ("192.168.0.2", "1234", "192.168.0.2:1234"),
            ("phone.local", "5555", "phone.local:5555"),
            ("2001:db8::2", "1234", "[2001:db8::2]:1234"),
            ("[fe80::123%en0]", "5555", "[fe80::123%en0]:5555")
        ] {
            let endpoint = Endpoint.address(host: host, port: port)
            XCTAssertEqual(endpoint, expected)
            XCTAssertTrue(Endpoint.valid(endpoint))
            XCTAssertEqual(Endpoint.host(endpoint), Endpoint.normalizedHost(host))
            XCTAssertEqual(Endpoint.port(endpoint), port)
        }
        for invalid in ["[::1]", "[::1]:", "[::1]:0", "[::1]:65536", "[::bad::]:55", "[fe80::1%]:55",
                        "[fe80::1%en0;echo]:55", "2001:db8::1:5555", "host:+55", "host: 55", "-host:55", "host\n:55"] {
            XCTAssertFalse(Endpoint.valid(invalid), invalid)
        }
        XCTAssertEqual(Endpoint.host("adb-phone._adb-tls-connect._tcp"), "adb-phone._adb-tls-connect._tcp")
    }
    func testLegacyPlatformDisablesOnlyUnsupportedOptionalFeatures() {
        let requested = MirrorConfiguration(maxSize: 1920, keepAwake: true, powerOn: false)
        let old = AndroidCapabilities(sdkOutput: "29\n")
        XCTAssertTrue(old.supportsMirroring)
        XCTAssertFalse(old.supportsAudio)
        let effective = old.configuration(for: requested)
        XCTAssertFalse(effective.audioEnabled)
        XCTAssertTrue(effective.serverArguments(scid: "123").contains("audio=false"))
        XCTAssertEqual(effective.maxSize, requested.maxSize)
        XCTAssertEqual(effective.keepAwake, requested.keepAwake)
        XCTAssertEqual(effective.powerOn, requested.powerOn)
        XCTAssertTrue(AndroidCapabilities(sdkOutput: "30").supportsAudio)
        XCTAssertFalse(AndroidCapabilities(sdkOutput: "20").supportsMirroring)
        XCTAssertFalse(AndroidCapabilities(sdkOutput: "23").supportsDirectText)
        XCTAssertTrue(AndroidCapabilities(sdkOutput: "24").supportsDirectText)
        for unknown in ["", "permission denied", "0", "-1"] {
            let capabilities = AndroidCapabilities(sdkOutput: unknown)
            XCTAssertNil(capabilities.sdk)
            XCTAssertEqual(capabilities.configuration(for: requested), requested)
        }
    }
    func testKeyguardFormattingVariantsAndConflictsRemainConservative() {
        XCTAssertEqual(PhoneLockState.parse("mIsShowing : TRUE"), .locked)
        XCTAssertEqual(PhoneLockState.parse("mKeyguardShowing = false"), .unlocked)
        XCTAssertEqual(PhoneLockState.parse("showing : true\n"), .locked)
        XCTAssertEqual(PhoneLockState.parse("mIsShowing : true\nmIsShowing = false"), .unknown)
        XCTAssertEqual(PhoneLockState.parse("isKeyguardSecure=true"), .unknown)
        XCTAssertEqual(KeyguardStatus.prompt("mBouncerVisible: TRUE"), .ready)
        XCTAssertEqual(KeyguardStatus.prompt("mBouncerVisible=true\nmAlternateBouncerShowing=true"), .hidden)
        XCTAssertEqual(KeyguardStatus.prompt("mPrimaryBouncerFullyShown=false\nisPrimaryBouncerShowingOrWillBeShowing : true"), .opening)
        XCTAssertEqual(KeyguardStatus.prompt("mBouncerShowing=true\nmBouncerShowing=false"), .unknown)
        XCTAssertFalse(KeyguardStatus.screenAwake("mScreenOnFully : false\nINTERACTIVE_STATE_AWAKE"))
        XCTAssertFalse(KeyguardStatus.screenAwake("mScreenOnFully=true\nmScreenOnFully=false"))
        XCTAssertTrue(KeyguardStatus.screenAwake("mScreenOnFully : true"))
    }
    func testPrimaryViewportTracksRotationAndIgnoresInactiveExternalDisplays() throws {
        let external = "DisplayViewport{valid=true, isActive=true, displayId=2, logicalFrame=[0, 0, 3840, 2160]}"
        let inactive = "DisplayViewport{valid=true, isActive=false, displayId=0, logicalFrame=[0, 0, 900, 900]}"
        let active = "DisplayViewport{type=INTERNAL, valid=true, isActive=true, displayId=0, orientation=1, logicalFrame=Rect(0, 0 - 2400, 1080), deviceWidth=2400, deviceHeight=1080}"
        XCTAssertEqual(AndroidDisplayGeometry.primaryViewport(external + inactive + active), CGSize(width: 2400, height: 1080))
        XCTAssertEqual(AndroidDisplayGeometry.primaryViewport("DisplayViewport{displayId=0, valid=true, logicalFrame=[0, 0, 1800, 2400]}"), CGSize(width: 1800, height: 2400))
        XCTAssertNil(AndroidDisplayGeometry.primaryViewport(external + inactive))
        XCTAssertNil(AndroidDisplayGeometry.primaryViewport("DisplayViewport{displayId=0, valid=false, logicalFrame=[0,0,100,100]}"))
        XCTAssertEqual(try AndroidDisplayGeometry.screenSize("Physical size: 1080x2400\nOverride size: 900x2000", orientation: CGSize(width: 2400, height: 1080)), CGSize(width: 2000, height: 900))
    }
    @MainActor func testPairingAcceptsIPv6HostsWithoutChangingPortMeaning() {
        let store = PairingStore()
        store.host = "fe80::abcd%en0"; store.pairPort = "40000"; store.code = "123456"
        XCTAssertTrue(store.canPair)
        XCTAssertFalse(store.canConnect)
        store.connectPort = "41000"
        XCTAssertTrue(store.canConnect)
        store.code = "12345a"
        XCTAssertFalse(store.canPair)
    }
    @MainActor func testSharedCommandPolicyRespectsLockStateAndViewOnly() {
        let domain = "com.lopleec.androidmirror.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = MirrorPreferences(defaults: defaults)
        let store = MirrorStore(preferences: preferences)
        store.phase = .connected
        store.handleLockState(.locked)
        XCTAssertFalse(store.isEnabled(.home))
        XCTAssertFalse(store.isEnabled(.screenshot))
        XCTAssertTrue(store.isEnabled(.unlock))
        store.handleLockState(.unlocked)
        XCTAssertTrue(store.isEnabled(.home))
        XCTAssertTrue(store.isEnabled(.screenshot))
        preferences.mode = .viewOnly
        XCTAssertFalse(store.isEnabled(.home))
        XCTAssertFalse(store.isEnabled(.unlock))
        XCTAssertFalse(store.isEnabled(.screenPower))
        XCTAssertTrue(store.isEnabled(.screenshot))
        store.disconnect()
    }
}
