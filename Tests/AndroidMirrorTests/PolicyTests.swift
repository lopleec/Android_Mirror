import XCTest
@testable import AndroidMirror

final class PolicyTests: XCTestCase {
    @MainActor func testLockOverlayBlocksMirrorClicksAndKeyboardDuringUnlock() {
        let store = MirrorStore(preferences: MirrorPreferences(defaults: isolatedDefaults()))
        store.phase = .connected
        XCTAssertFalse(store.acceptsPhoneInput) // Unknown state/connecting overlay.
        store.handleLockState(.unlocked)
        XCTAssertTrue(store.acceptsPhoneInput)
        let view = PhoneInputView(store: store)
        XCTAssertTrue(view.acceptsFirstResponder)
        store.unlockPresented = true
        XCTAssertFalse(store.acceptsPhoneInput)
        XCTAssertFalse(view.acceptsFirstResponder)
        store.unlockPresented = false
        store.handleLockState(.locked)
        XCTAssertFalse(store.acceptsPhoneInput)
        XCTAssertFalse(view.acceptsFirstResponder)
        view.cancelInput()
        store.disconnect()
    }
    @MainActor func testViewOnlyDoesNotWakePhoneOrChangeTimeout() {
        let defaults = isolatedDefaults()
        let preferences = MirrorPreferences(defaults: defaults)
        preferences.autoScreenOff = true
        preferences.mode = .viewOnly
        XCTAssertFalse(preferences.mode.allowsInput)
        let args = preferences.configuration.serverArguments(scid: "123")
        XCTAssertTrue(args.contains("power_on=false"))
        XCTAssertFalse(args.contains { $0.hasPrefix("screen_off_timeout=") })
        let store = MirrorStore(preferences: preferences)
        store.phase = .connected
        XCTAssertFalse(store.canControl)
        store.key(26); store.input(ScreenCommand.display(on: false)); store.toggleScreen()
        XCTAssertFalse(store.screenOff)
        preferences.mode = .control
        XCTAssertTrue(store.canControl)
    }
    @MainActor func testPreferencesPersistAndOriginalResolutionIsPreserved() {
        let defaults = isolatedDefaults()
        let first = MirrorPreferences(defaults: defaults)
        XCTAssertTrue(first.keepAwake)
        XCTAssertFalse(first.autoScreenOff)
        first.mode = .viewOnly; first.maxSize = 0; first.keepAwake = false
        first.autoScreenOff = true; first.autoReconnect = false; first.clipboardSync = false
        XCTAssertEqual(first.authenticationMinutes, 10)
        first.authenticationMinutes = 5
        let restored = MirrorPreferences(defaults: defaults)
        XCTAssertEqual(restored.mode, .viewOnly)
        XCTAssertEqual(restored.maxSize, 0)
        XCTAssertFalse(restored.keepAwake)
        XCTAssertTrue(restored.autoScreenOff)
        XCTAssertFalse(restored.autoReconnect)
        XCTAssertFalse(restored.clipboardSync)
        XCTAssertEqual(restored.authenticationMinutes, 5)
    }
    func testKeepAwakeUsesRestorableDeviceTimeoutAndWakeIsNotPowerToggle() {
        let args = MirrorConfiguration(maxSize: 1920, keepAwake: true, powerOn: true).serverArguments(scid: "123")
        XCTAssertTrue(args.contains("screen_off_timeout=2147483647"))
        XCTAssertTrue(args.contains("cleanup=true"))
        let commands = ScreenCommand.wake(showPhysicalScreen: false)
        XCTAssertEqual(commands[0], Data([10, 0]))
        XCTAssertEqual(commands[1].integer(at: 2, as: UInt32.self), 224)
        XCTAssertEqual(commands[2].integer(at: 2, as: UInt32.self), 224)
        XCTAssertEqual(commands[1][1], 0)
        XCTAssertEqual(commands[2][1], 1)
    }
    @MainActor func testTransportsDeduplicateAndSavedDeviceReconnectsAtNewAddress() async throws {
        let defaults = isolatedDefaults()
        let ip = Device(id: "192.168.1.3:34231", name: "Pixel 9a", state: "device")
        let mdns = Device(id: "adb-pixel-random._adb-tls-connect._tcp", name: "Pixel 9a", state: "device")
        let adb = FakeADB(devices: [ip, mdns], identities: [ip.id: "pixel", mdns.id: "pixel"])
        let registry = DeviceRegistry(adb: adb, defaults: defaults)
        try await registry.refresh(autoReconnect: true)
        XCTAssertEqual(registry.devices, [ip])
        XCTAssertEqual(registry.device(for: mdns.id), ip)
        await registry.remember(ip); await registry.remember(mdns)
        XCTAssertEqual(registry.saved.count, 1)
        XCTAssertTrue(registry.isOnline(registry.saved[0]))
        let record = registry.saved[0]
        let newService = WirelessService(name: "adb-pixel-new", kind: "_adb-tls-connect._tcp", endpoint: "192.168.1.9:40000")
        let unrelated = WirelessService(name: "adb-other-new", kind: "_adb-tls-connect._tcp", endpoint: "192.168.1.10:40000")
        await adb.setOffline(services: [unrelated, newService])
        let loaded = DeviceRegistry(adb: adb, defaults: defaults)
        XCTAssertEqual(loaded.saved, [record])
        try await loaded.refresh(autoReconnect: true)
        let endpointsAfterDiscovery = await adb.connectedEndpoints()
        XCTAssertEqual(endpointsAfterDiscovery, [newService.endpoint])
        let connected = try await loaded.reconnect(record)
        XCTAssertEqual(connected.id, newService.endpoint)
        let endpointsAfterReconnect = await adb.connectedEndpoints()
        XCTAssertEqual(endpointsAfterReconnect, [newService.endpoint])
        loaded.forget(record)
        XCTAssertTrue(DeviceRegistry(adb: adb, defaults: defaults).saved.isEmpty)
    }
    @MainActor func testChangedAddressCannotSelectUnrelatedPhone() async throws {
        let endpoint = "192.168.1.3:34231"
        let adb = FakeADB(devices: [], identities: [endpoint: "other"])
        let registry = DeviceRegistry(adb: adb, defaults: isolatedDefaults())
        let saved = SavedDevice(id: "pixel", name: "Pixel", transportID: "old:4000", endpoint: endpoint)
        do { _ = try await registry.reconnect(saved); XCTFail("Should reject a reused address") }
        catch { XCTAssertEqual(error.localizedDescription, L10n.tr("This address now belongs to another phone. Rediscover your saved device.")) }
    }
    @MainActor func testAutoScreenOffWaitsForUnlockAndNeverInjectsWake() async throws {
        let preferences = MirrorPreferences(defaults: isolatedDefaults())
        let controller = ScreenController(preferences: preferences)
        let transport = FakeScreenTransport()
        controller.attach(transport, autoScreenOff: true)
        XCTAssertTrue(transport.commands.isEmpty)
        controller.updateLockState(.locked)
        XCTAssertTrue(transport.commands.isEmpty)
        controller.updateLockState(.unlocked)
        XCTAssertEqual(transport.commands, [Data([10, 0])])
        XCTAssertTrue(controller.physicalScreenOff)
        // Regression: the old repeating timer emitted WAKEUP after 3 seconds, flashing the display.
        try await Task.sleep(for: .milliseconds(3500))
        for _ in 0..<10 { controller.updateLockState(.unlocked) }
        XCTAssertEqual(transport.commands, [Data([10, 0])])
        XCTAssertTrue(preferences.configuration.serverArguments(scid: "123").contains("screen_off_timeout=2147483647"))
        controller.showForUnlock()
        XCTAssertEqual(transport.commands.last, Data([10, 1]))
        XCTAssertFalse(controller.physicalScreenOff)
        controller.updateLockState(.unlocked)
        XCTAssertEqual(transport.commands.last, Data([10, 0]))
        XCTAssertTrue(controller.detach())
    }
    @MainActor func testManualScreenOffSendsOnlyDisplayPowerAndViewOnlyDoesNotAutoOff() {
        let preferences = MirrorPreferences(defaults: isolatedDefaults())
        let controller = ScreenController(preferences: preferences)
        let transport = FakeScreenTransport()
        preferences.mode = .viewOnly
        controller.attach(transport, autoScreenOff: true)
        controller.updateLockState(.unlocked)
        XCTAssertTrue(transport.commands.isEmpty)
        preferences.mode = .control
        controller.setPhysicalScreen(off: true)
        XCTAssertEqual(transport.commands, [Data([10, 0])])
        controller.setPhysicalScreen(off: false)
        XCTAssertEqual(Array(transport.commands.dropFirst()), ScreenCommand.wake(showPhysicalScreen: true))
        XCTAssertFalse(controller.detach())
        controller.setPhysicalScreen(off: true)
        XCTAssertEqual(transport.commands.count, 4)
    }
    @MainActor func testDeviceRenameSurvivesDiscoveryAndForgetStaysRemoved() async throws {
        let defaults = isolatedDefaults()
        let phone = Device(id: "192.168.1.8:4000", name: "Pixel 9a", state: "device")
        let adb = FakeADB(devices: [phone], identities: [phone.id: "physical-pixel"])
        let registry = DeviceRegistry(adb: adb, defaults: defaults)
        try await registry.refresh(autoReconnect: false)
        await registry.remember(phone)
        XCTAssertEqual(registry.credentialAccount(for: phone), "physical-pixel")
        registry.rename(registry.saved[0], to: "我的 Pixel")
        await registry.remember(phone)
        XCTAssertEqual(registry.saved[0].name, "我的 Pixel")
        XCTAssertEqual(registry.device(for: "physical-pixel"), phone)
        registry.forget(registry.saved[0])
        try await registry.refresh(autoReconnect: true)
        XCTAssertTrue(registry.devices.isEmpty)
        let restored = DeviceRegistry(adb: adb, defaults: defaults)
        try await restored.refresh(autoReconnect: true)
        XCTAssertTrue(restored.devices.isEmpty)
        try await restored.allowDevice(phone.id)
        XCTAssertEqual(restored.devices, [phone])
    }
    private func isolatedDefaults() -> UserDefaults {
        let name = "com.lopleec.androidmirror.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}

private actor FakeADB: ADBTransport {
    private var current: [Device]
    private var identities: [String: String]
    private var broadcasts: [WirelessService] = []
    private var connections: [String] = []
    init(devices: [Device], identities: [String: String]) { current = devices; self.identities = identities }
    func run(_ arguments: [String], timeout: TimeInterval) async throws -> String { identities[arguments[1]] ?? arguments[1] }
    func devices() async throws -> [Device] { current }
    func services() async throws -> [WirelessService] { broadcasts }
    func connect(_ endpoint: String) async throws {
        connections.append(endpoint)
        current.append(Device(id: endpoint, name: "Pixel 9a", state: "device"))
        if let service = broadcasts.first(where: { $0.endpoint == endpoint }) {
            identities[endpoint] = service.name.components(separatedBy: "-")[1]
        }
    }
    func setOffline(services: [WirelessService]) { current = []; broadcasts = services }
    func connectedEndpoints() -> [String] { connections }
}

private final class FakeScreenTransport: ScreenTransport {
    var commands: [Data] = []
    func send(_ command: Data) { commands.append(command) }
}
