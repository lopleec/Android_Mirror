import XCTest
@testable import AndroidMirror

final class UnlockInputPreparationTests: XCTestCase {
    @MainActor func testUnavailableUHIDFallsBackBeforeAnyKeyboardAttachment() async throws {
        let keyboard = TestUnlockKeyboard()
        var attached = false
        let method = try await UnlockInputPreparation(adb: KeyboardADB(uhidAvailable: false)).prepare(
            session: keyboard, requested: .physical, keyboardAttached: false, onAttached: { attached = true }
        )
        XCTAssertEqual(method, .compatibility)
        XCTAssertEqual(keyboard.attachments, 0)
        XCTAssertFalse(attached)
    }
    @MainActor func testAttachmentIsRecordedAndReusedAcrossNavigationAttempts() async throws {
        let keyboard = TestUnlockKeyboard()
        let adb = KeyboardADB(uhidAvailable: true)
        var attached = false
        let preparation = UnlockInputPreparation(adb: adb)
        let first = try await preparation.prepare(session: keyboard, requested: .physical, keyboardAttached: attached, onAttached: { attached = true })
        let second = try await preparation.prepare(session: keyboard, requested: .physical, keyboardAttached: attached, onAttached: { attached = true })
        XCTAssertEqual(first, .physical)
        XCTAssertEqual(second, .physical)
        XCTAssertTrue(attached)
        XCTAssertEqual(keyboard.attachments, 1)
    }
    @MainActor func testExplicitCompatibilityDoesNotProbeOrRegisterKeyboard() async throws {
        let keyboard = TestUnlockKeyboard()
        let adb = KeyboardADB(uhidAvailable: true)
        let method = try await UnlockInputPreparation(adb: adb).prepare(session: keyboard, requested: .compatibility, keyboardAttached: false, onAttached: {})
        XCTAssertEqual(method, .compatibility)
        XCTAssertEqual(keyboard.attachments, 0)
        let commands = await adb.commands
        XCTAssertTrue(commands.isEmpty)
    }
}

private final class TestUnlockKeyboard: UnlockKeyboardTransport, @unchecked Sendable {
    let device = Device(id: "test", name: "Android", state: "device")
    private let lock = NSLock()
    private var count = 0
    var attachments: Int { lock.withLock { count } }
    func openUnlockKeyboard() async throws { lock.withLock { count += 1 } }
}
private actor KeyboardADB: ADBTransport {
    let uhidAvailable: Bool
    var commands: [[String]] = []
    init(uhidAvailable: Bool) { self.uhidAvailable = uhidAvailable }
    func run(_ arguments: [String], timeout: TimeInterval) async throws -> String {
        commands.append(arguments)
        if !uhidAvailable { throw MirrorError.message("Permission denied") }
        return ""
    }
    func devices() async throws -> [Device] { [] }
    func services() async throws -> [WirelessService] { [] }
    func connect(_ endpoint: String) async throws {}
}
