import XCTest
@testable import AndroidMirror

final class UnlockPreparationTests: XCTestCase {
    func testOptionalLivePreparationWithoutSendingAnyCredential() async throws {
        guard let serial = ProcessInfo.processInfo.environment["ANDROIDMIRROR_TEST_UNLOCK_DEVICE"] else {
            throw XCTSkip("Set a connected device explicitly for the credential-free preparation check")
        }
        let device = Device(id: serial, name: "Test Android", state: "device")
        if ProcessInfo.processInfo.environment["ANDROIDMIRROR_TEST_REQUIRE_LOCKED"] == "1" {
            var locked = false
            for _ in 0..<60 {
                let policy = try await ADBClient().run(["-s", serial, "shell", "dumpsys", "window", "policy"], timeout: 4)
                if PhoneLockState.parse(policy) == .locked { locked = true; break }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard locked else { throw XCTSkip("Phone has not reached a credential-required lock state") }
        }
        var session: MirrorSession?
        if ProcessInfo.processInfo.environment["ANDROIDMIRROR_TEST_UNLOCK_KEYBOARD"] == "1" {
            let mirror = MirrorSession(device: device); session = mirror
            try await mirror.start(configuration: MirrorConfiguration(maxSize: 1280, keepAwake: false, powerOn: false, audioEnabled: false))
            try await mirror.openUnlockKeyboard()
        }
        let started = ProcessInfo.processInfo.systemUptime
        let result: Bool
        do { result = try await UnlockPreparation(adb: ADBClient()).prepare(device: device, videoSize: size) }
        catch { await session?.stop().value; throw error }
        print("LIVE_UNLOCK_PREPARATION_SECONDS: \(ProcessInfo.processInfo.systemUptime - started)")
        if result {
            let editor = await KeyguardPromptNavigator(adb: ADBClient()).prepare(device)
            print("LIVE_KEYGUARD_EDITOR_VISIBLE: \(editor)")
        }
        await session?.stop().value
        if !result, ProcessInfo.processInfo.environment["ANDROIDMIRROR_TEST_REQUIRE_LOCKED"] == "1" {
            throw XCTSkip("Phone unlocked itself before credential entry; no credential sent")
        }
        // Either an already-unlocked phone or a confirmed prompt is a successful preparation.
        print(result ? "LIVE_UNLOCK_PREPARATION: credential prompt ready; no credential sent" : "LIVE_UNLOCK_PREPARATION: phone already unlocked; no credential sent")
    }
    func testOneRequestWakesThenWaitsForReadyPromptWithoutEnterOrPasswordInADB() async throws {
        let adb = PreparationADB()
        let pauses = PreparationPauses()
        let result = try await UnlockPreparation(adb: adb, pause: { await pauses.record($0) }).prepare(device: device, videoSize: size)
        XCTAssertTrue(result)
        let commands = await adb.commands
        XCTAssertEqual(commands.filter { $0.suffix(3) == ["input", "keyevent", "224"] }.count, 1)
        XCTAssertEqual(commands.filter { $0.contains("swipe") }.count, 1)
        XCTAssertFalse(commands.contains { $0.contains("dismiss-keyguard") || $0.contains("66") || $0.contains("text") || $0.contains("82") || $0.contains("tap") })
        XCTAssertGreaterThan(commands.filter { $0.contains("policy") }.count, 3)
        XCTAssertFalse(commands.contains { $0.contains("push") || $0.contains("app_process") })
        let waiting = await pauses.total
        XCTAssertLessThanOrEqual(waiting, .milliseconds(350), "Ready credentials must not wait through helper startup or extra fixed delays")
    }
    func testSwipeUsesPhysicalOverrideSizeAndOneGesture() async throws {
        let adb = PreparationADB(alternateBouncer: true)
        let ready = try await UnlockPreparation(adb: adb, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertTrue(ready)
        let commands = await adb.commands
        let swipe = try XCTUnwrap(commands.first { $0.contains("swipe") })
        XCTAssertEqual(Array(swipe.suffix(7)), ["input", "swipe", "300", "2484", "300", "810", "220"])
        XCTAssertEqual(commands.filter { $0.contains("swipe") }.count, 1)
    }
    func testFirstWakeWaitsForFullyLitDisplayBeforeSwipingAwayFromFingerprint() async throws {
        let adb = PreparationADB(alternateBouncer: true, wakeTransitionReads: 2)
        let ready = try await UnlockPreparation(adb: adb, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertTrue(ready)
        let commands = await adb.commands
        let wake = try XCTUnwrap(commands.firstIndex { $0.contains("224") })
        let swipe = try XCTUnwrap(commands.firstIndex { $0.contains("swipe") })
        XCTAssertEqual(commands[(wake + 1)..<swipe].filter { $0.contains("policy") }.count, 3)
        XCTAssertEqual(Array(commands[swipe].suffix(7)), ["input", "swipe", "300", "2484", "300", "810", "220"])
    }
    func testGestureUsesPrimaryViewportBeforeFirstVideoFrame() async throws {
        let adb = PreparationADB(viewport: "DisplayViewport{valid=true, isActive=true, displayId=0, logicalFrame=Rect(0, 0 - 2400, 1080)}")
        let ready = try await UnlockPreparation(adb: adb, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertTrue(ready)
        let commands = await adb.commands
        let swipe = try XCTUnwrap(commands.first { $0.contains("swipe") })
        XCTAssertEqual(Array(swipe.suffix(5)), ["600", "993", "600", "324", "220"])
    }
    func testViewportSurvivesUnavailableWMAndExistingPromptNeedsNoGeometry() async throws {
        let viewport = "DisplayViewport{valid=true, isActive=true, displayId=0, logicalFrame=[0,0,1080,2400]}"
        let adb = PreparationADB(viewport: viewport, wmAvailable: false)
        let ready = try await UnlockPreparation(adb: adb, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertTrue(ready)
        let commands = await adb.commands
        XCTAssertEqual(commands.filter { $0.contains("swipe") }.count, 1)
        let existing = PreparationADB(promptAlreadyVisible: true, wmAvailable: false)
        let existingReady = try await UnlockPreparation(adb: existing, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertTrue(existingReady)
        let existingCommands = await existing.commands
        XCTAssertFalse(existingCommands.contains { $0.contains("swipe") })
    }
    func testMissingVisibilityAndManualUnlockRaceNeverAuthorizeCredentialSend() async throws {
        let unavailable = PreparationADB(missingPrompt: true)
        do { _ = try await UnlockPreparation(adb: unavailable, pause: { _ in }).prepare(device: device, videoSize: size); XCTFail() }
        catch { XCTAssertEqual(error.localizedDescription, L10n.tr("Could not confirm the phone password screen. Open it on your phone and try again. No password was sent.")) }
        let manual = PreparationADB(manualUnlock: true)
        let ready = try await UnlockPreparation(adb: manual, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertFalse(ready)
    }
    func testFailedSwipeNeverFallsBackToBiometricButtonsOrNavigationKeys() async throws {
        let adb = PreparationADB(swipeWorks: false, alternateBouncer: true)
        do {
            _ = try await UnlockPreparation(adb: adb, pause: { _ in }).prepare(device: device, videoSize: size)
            XCTFail("A biometric panel must never authorize password entry")
        } catch { XCTAssertEqual(error.localizedDescription, L10n.tr("Could not confirm the phone password screen. Open it on your phone and try again. No password was sent.")) }
        let commands = await adb.commands
        XCTAssertEqual(commands.filter { $0.contains("swipe") }.count, 3)
        XCTAssertFalse(commands.contains { $0.contains("66") || $0.contains("82") || $0.contains("text") || $0.contains("dismiss-keyguard") || $0.contains("tap") })
        XCTAssertFalse(commands.contains { $0.contains("push") || $0.contains("app_process") })
    }
    func testDroppedFirstSwipeRecoversWithinOneRequestWithoutSendingCredentials() async throws {
        let adb = PreparationADB(alternateBouncer: true, minimumSwipes: 2)
        let ready = try await UnlockPreparation(adb: adb, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertTrue(ready)
        let commands = await adb.commands
        XCTAssertEqual(commands.filter { $0.contains("swipe") }.count, 2)
        XCTAssertEqual(commands.filter { $0.contains("224") }.count, 1)
        XCTAssertFalse(commands.contains { $0.contains("tap") || $0.contains("text") || $0.contains("66") || $0.contains("82") })
        let manual = PreparationADB(manualUnlock: true, minimumSwipes: 2)
        let raceReady = try await UnlockPreparation(adb: manual, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertFalse(raceReady)
        let raceCommands = await manual.commands
        XCTAssertEqual(raceCommands.filter { $0.contains("swipe") }.count, 1)
    }
    func testScheduledPasswordPageIsNotReadyAndDoesNotReceiveAnotherSwipe() async throws {
        let adb = PreparationADB(promptAlreadyVisible: true, openingReads: 3)
        let ready = try await UnlockPreparation(adb: adb, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertTrue(ready)
        let commands = await adb.commands
        XCTAssertFalse(commands.contains { $0.contains("swipe") || $0.contains("push") })
        XCTAssertGreaterThanOrEqual(commands.filter { $0.contains("service") }.count, 5)
    }
    func testExistingPasswordPageSkipsWakeSwipeAndHelper() async throws {
        let adb = PreparationADB(promptAlreadyVisible: true)
        let ready = try await UnlockPreparation(adb: adb, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertTrue(ready)
        let commands = await adb.commands
        XCTAssertFalse(commands.contains { $0.contains("224") || $0.contains("swipe") || $0.contains("push") || $0.contains("app_process") })
    }
    func testUnknownVendorStateUsesOnlyOneHelperWithFreshLockCheck() async throws {
        let adb = PreparationADB(missingPrompt: true, helperVisible: true)
        let ready = try await UnlockPreparation(adb: adb, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertTrue(ready)
        let commands = await adb.commands
        XCTAssertEqual(commands.filter { $0.contains("app_process") }.count, 1)
        let manual = PreparationADB(missingPrompt: true, manualUnlock: true, helperVisible: true)
        let raceReady = try await UnlockPreparation(adb: manual, pause: { _ in }).prepare(device: device, videoSize: size)
        XCTAssertFalse(raceReady)
    }
    func testReadinessRejectsHistoryAlternateBiometricsAndInconsistentStates() throws {
        XCTAssertNil(UnlockPreparation.promptVisible("bouncerWasShowingWhenHidden=true\nisAlternateBouncerShowing=true"))
        XCTAssertEqual(UnlockPreparation.promptVisible("isPrimaryBouncerShowingOrWillBeShowing=false\nisAlternateBouncerShowing=true\nisBouncerShowing(): true"), false)
        XCTAssertEqual(UnlockPreparation.promptVisible("isAlternateBouncerShowing=true\nisBouncerShowing(): true"), false)
        XCTAssertEqual(UnlockPreparation.promptVisible("isPrimaryBouncerShowingOrWillBeShowing=true\nisAlternateBouncerShowing=false\nisBouncerShowing(): true"), true)
        XCTAssertNil(UnlockPreparation.promptVisible("isPrimaryBouncerShowingOrWillBeShowing=true\nisBouncerShowing(): false"))
        XCTAssertEqual(UnlockPreparation.promptState("isPrimaryBouncerFullyShown=false\nisPrimaryBouncerShowingOrWillBeShowing=true"), .opening)
        XCTAssertEqual(UnlockPreparation.promptVisible("isBouncerShowing(): false\nmBouncerVisible=true"), false)
        XCTAssertNil(UnlockPreparation.promptVisible("mBouncerShowing=true\nmBouncerShowing=false"))
        XCTAssertTrue(UnlockPreparation.promptVisible("bouncerShowing: true") == true)
        XCTAssertFalse(UnlockPreparation.screenAwake("screenState=SCREEN_STATE_OFF\ninteractiveState=INTERACTIVE_STATE_AWAKE"))
        XCTAssertFalse(UnlockPreparation.screenAwake("screenState=SCREEN_STATE_TURNING_ON\ninteractiveState=INTERACTIVE_STATE_AWAKE"))
        XCTAssertFalse(UnlockPreparation.screenAwake("screenState=SCREEN_STATE_ON\nmScreenOnFully=false"))
        XCTAssertFalse(UnlockPreparation.screenAwake("screenState=SCREEN_STATE_ON\ninteractiveState=INTERACTIVE_STATE_GOING_TO_SLEEP"))
        XCTAssertThrowsError(try UnlockPreparation.screenSize("permission denied", orientation: size))
        let landscape = try UnlockPreparation.screenSize("Physical size: 1080x2400", orientation: CGSize(width: 1000, height: 500))
        XCTAssertEqual(landscape, CGSize(width: 2400, height: 1080))
    }
    func testCancelledWorkflowStopsBeforeDeviceCommands() async throws {
        let adb = PreparationADB()
        let task = Task {
            try Task.checkCancellation()
            return try await UnlockPreparation(adb: adb, pause: { _ in }).prepare(device: device, videoSize: size)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    private var device: Device { Device(id: "test-device", name: "Other Android", state: "device") }
    private var size: CGSize { CGSize(width: 1080, height: 2400) }
}

private actor PreparationADB: ADBTransport {
    var commands: [[String]] = []
    private var stage = 0, promptReads = 0
    private var wakeTransitionReads: Int
    private var swipeCount = 0, openingReads: Int
    private let minimumSwipes: Int
    let viewport: String
    let wmAvailable: Bool
    let swipeWorks: Bool, missingPrompt: Bool, manualUnlock: Bool, alternateBouncer: Bool, helperVisible: Bool
    init(swipeWorks: Bool = true, missingPrompt: Bool = false, manualUnlock: Bool = false, alternateBouncer: Bool = false,
         promptAlreadyVisible: Bool = false, helperVisible: Bool = false, wakeTransitionReads: Int = 0,
         minimumSwipes: Int = 1, openingReads: Int = 0, viewport: String = "", wmAvailable: Bool = true) {
        self.wmAvailable = wmAvailable
        self.viewport = viewport
        self.swipeWorks = swipeWorks; self.missingPrompt = missingPrompt; self.manualUnlock = manualUnlock
        self.alternateBouncer = alternateBouncer
        self.helperVisible = helperVisible
        self.wakeTransitionReads = wakeTransitionReads
        self.minimumSwipes = minimumSwipes; self.openingReads = openingReads
        if promptAlreadyVisible { stage = 2 }
    }
    func run(_ arguments: [String], timeout: TimeInterval) async throws -> String {
        commands.append(arguments)
        if arguments.suffix(2) == ["dumpsys", "input"] { return viewport }
        if arguments.contains("policy") {
            let lock = manualUnlock && promptReads >= 2 ? "false" : "true"
            if stage == 1, wakeTransitionReads > 0 {
                wakeTransitionReads -= 1
                return "mIsShowing=\(lock)\nscreenState=SCREEN_STATE_TURNING_ON\ninteractiveState=INTERACTIVE_STATE_AWAKE\nmScreenOnFully=false"
            }
            return "mIsShowing=\(lock)\nscreenState=SCREEN_STATE_\(stage == 0 ? "OFF" : "ON")"
        }
        if arguments.contains("service") {
            promptReads += 1
            if missingPrompt { return "unsupported" }
            let primary = stage >= 2
            if primary, openingReads > 0 {
                openingReads -= 1
                return "isPrimaryBouncerFullyShown=false\nisPrimaryBouncerShowingOrWillBeShowing=true\nisBouncerShowing(): false"
            }
            return "isPrimaryBouncerShowingOrWillBeShowing=\(primary)\nisAlternateBouncerShowing=\(alternateBouncer && !primary)\nisBouncerShowing(): \(primary || alternateBouncer)"
        }
        if arguments.contains("224") { stage = 1 }
        if arguments.contains("swipe") {
            swipeCount += 1
            if swipeWorks, swipeCount >= minimumSwipes { stage = 2 }
        }
        if arguments.contains("app_process"), helperVisible { return "MIRROR_KEYGUARD:VISIBLE" }
        if arguments.suffix(2) == ["wm", "size"] {
            if !wmAvailable { throw MirrorError.message("Unavailable wm command") }
            return "Physical size: 1080x2400\nOverride size: 1200x2700" }
        return ""
    }
    func devices() async throws -> [Device] { [] }
    func services() async throws -> [WirelessService] { [] }
    func connect(_ endpoint: String) async throws {}
}

private actor PreparationPauses {
    var total: Duration = .zero
    func record(_ duration: Duration) { total += duration }
}
