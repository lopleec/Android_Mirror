import SwiftUI
import AppKit
import AVFoundation
import Observation

/// Coordinates a single mirror session; discovery, preferences, clipboard and screen policy are independent.
@MainActor @Observable
final class MirrorStore {
    let preferences: MirrorPreferences
    let registry: DeviceRegistry
    let credentials: PhoneCredentialStore
    let screen: ScreenController
    var selectedID: String?
    var phase: Phase = .idle
    var error: String?
    var pairingPresented = false
    private(set) var hasVideo = false
    private(set) var phoneLockState: PhoneLockState = .unknown
    var unlockPresented = false
    private(set) var unlockSending = false
    private(set) var unlockMessage: String?
    private var unlockKeyboardActive = false
    var size = CGSize(width: 1080, height: 2400)
    private(set) var session: MirrorSession?
    let displayLayer = AVSampleBufferDisplayLayer()
    private let clipboard: ClipboardBridge
    private let adb = ADBClient()
    private let lockMonitor = PhoneLockMonitor()
    @ObservationIgnored private var presenter: VideoFramePresenter?
    private var generation = UUID()
    private var unlockAttempt: UnlockAttempt?
    private var unlockExpiryTask: Task<Void, Never>?
    private var unlockTask: Task<Void, Never>?
    private(set) var authenticating = false
    private(set) var recoveringVideo = false
    private(set) var connectionIntent: MirrorConnectionIntent = .standard
    @ObservationIgnored private var lastUSBIDs: Set<String> = []
    @ObservationIgnored private var pendingUSBID: String?

    private struct UnlockAttempt {
        let account: String
        let password: String
        let method: UnlockInputMethod
    }
    private var unicodeInput: UnicodeInputSession?
    private var typingTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?

    enum Phase: Equatable { case idle, starting, connected }
    var devices: [Device] { registry.devices }
    var current: Device? { session?.device ?? selectedID.flatMap(registry.device(for:)) }
    var selectedRecord: SavedDevice? {
        if let current { return registry.record(for: current) }
        return registry.saved.first { $0.id == selectedID || $0.transportID == selectedID }
    }
    var deviceName: String { current.map(registry.displayName(for:)) ?? selectedRecord?.name ?? L10n.tr("Android Phone") }
    var credentialAccount: String? { current.flatMap(registry.credentialAccount(for:)) ?? selectedRecord?.id }
    var hasSavedPassword: Bool { credentials.contains(credentialAccount) }
    var hasSelection: Bool { current != nil || selectedRecord != nil }
    var connected: Bool { phase == .connected }
    var canControl: Bool { connected && preferences.mode.allowsInput && connectionIntent.allowsControl }
    var canRequestUnlock: Bool { connectionIntent.allowsControl && (preferences.mode.allowsInput || isUSBConnection) }
    var isUSBConnection: Bool { current.map { $0.ready && !$0.wireless } ?? false }
    var showsUnlockOverlay: Bool { connectionIntent.showsUnlock(state: phoneLockState, requested: unlockPresented) }
    var showsConnectingOverlay: Bool {
        phase == .starting || !hasVideo || connectionIntent.waitsForLockState(phoneLockState)
    }
    var acceptsPhoneInput: Bool { canControl && phoneLockState == .unlocked && !unlockPresented && !unlockSending }
    var screenOff: Bool { screen.physicalScreenOff }

    init(preferences: MirrorPreferences? = nil, registry: DeviceRegistry? = nil, credentials: PhoneCredentialStore? = nil) {
        let preferences = preferences ?? MirrorPreferences()
        self.preferences = preferences; self.registry = registry ?? DeviceRegistry()
        self.credentials = credentials ?? PhoneCredentialStore()
        clipboard = ClipboardBridge(preferences: preferences)
        screen = ScreenController(preferences: preferences)
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
    }
    func begin() {
        guard discoveryTask == nil else { return }
        discoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
    @discardableResult
    func shutdown() -> Task<Void, Never>? {
        discoveryTask?.cancel(); discoveryTask = nil; credentials.clearAutofill(); return disconnect()
    }
    func refresh() async {
        do {
            try await registry.refresh(autoReconnect: preferences.autoReconnect, activeTransportID: session?.device.id)
            let usb = registry.usbDevices
            let newUSB = usb.first { !lastUSBIDs.contains($0.id) }
            lastUSBIDs = Set(usb.map(\.id))
            if let newUSB { pendingUSBID = newUSB.id }
            if let pendingUSBID, !lastUSBIDs.contains(pendingUSBID) { self.pendingUSBID = nil }
            // Physical attachment selects an authorized phone, never starts a session or reads a password.
            if phase == .idle, !authenticating, !credentials.busy,
               let attached = usb.first(where: { $0.id == pendingUSBID }) ?? (!isUSBConnection && current?.ready != true ? usb.first : nil) {
                selectedID = attached.id; pairingPresented = false; error = nil
                pendingUSBID = nil
            }
            if selectedID == nil || (phase == .idle && current == nil && selectedRecord == nil) {
                selectedID = registry.saved.first?.id ?? devices.first(where: \.ready)?.id ?? devices.first?.id
            }
        } catch { if devices.isEmpty && phase == .idle { self.error = error.localizedDescription } }
    }
    func selectDevice(_ id: String) {
        guard selectedID != id, selectedRecord?.id != id else { return }
        disconnect(); selectedID = id; pairingPresented = false; error = nil
    }
    func connect(intent: MirrorConnectionIntent = .standard) {
        guard phase == .idle else { return }
        guard hasSelection else { pairingPresented = true; return }
        connectionIntent = intent
        if intent == .direct { clearUnlockAttempt(); dismissUnlock() }
        error = nil; phase = .starting; hasVideo = false; phoneLockState = .unknown
        let id = UUID(); generation = id
        let record = selectedRecord
        let available = current
        Task {
            do {
                let device: Device
                if let available, available.ready { device = available }
                else if let record { device = try await registry.reconnect(record) }
                else { throw MirrorError.message(L10n.tr("Allow debugging on your phone, then connect.")) }
                guard generation == id else { return }
                if let attempt = unlockAttempt, registry.credentialAccount(for: device) != attempt.account {
                    throw MirrorError.message(L10n.tr("The device identity has changed. No password was sent. Select your phone again."))
                }
                selectedID = device.id
                let session = MirrorSession(device: device)
                self.session = session
                displayLayer.flushAndRemoveImage()
                let presenter = VideoFramePresenter(layer: displayLayer) { [weak self] size in
                    guard let self, self.generation == id else { return }
                    if self.size != size { self.size = size }
                    self.hasVideo = true; self.recoveringVideo = false
                }
                self.presenter = presenter
                session.onFrame = { [weak presenter] sample, size in presenter?.offer(sample, size: size) }
                session.onClipboard = { [weak self] text in
                    DispatchQueue.main.async {
                        guard let self, self.generation == id, self.phoneLockState == .unlocked, !self.unlockPresented else { return }
                        self.clipboard.receive(text)
                    }
                }
                session.onError = { [weak self] message in
                    DispatchQueue.main.async {
                        guard let self, self.generation == id else { return }
                        self.disconnect(); self.error = message
                    }
                }
                session.onAudioWarning = { [weak self] message in
                    DispatchQueue.main.async {
                        guard let self, self.generation == id else { return }; self.error = message
                    }
                }
                try await session.start(configuration: intent.configuration(from: preferences.configuration))
                guard generation == id else { session.stop(); return }
                phase = .connected
                clipboard.attach(session, suspended: true)
                screen.attach(session, autoScreenOff: intent.allowsControl && preferences.mode.allowsInput && preferences.autoScreenOff)
                lockMonitor.start(device: device) { [weak self] state in
                    guard let self, self.generation == id else { return }
                    self.handleLockState(state)
                }
                await registry.remember(device)
            } catch {
                guard generation == id else { return }
                disconnect(); self.error = error.localizedDescription
            }
        }
    }
    func handleLockState(_ state: PhoneLockState) {
        let previous = phoneLockState
        phoneLockState = state
        if state == .locked, connectionIntent.allowsControl, let attempt = unlockAttempt {
            submitUnlock(attempt.password, method: attempt.method)
        } else if state == .unlocked {
            clearUnlockAttempt()
            dismissUnlock(); unlockMessage = nil
            if previous == .locked {
                // Protected keyguard capture can leave both the video and audio encoders stale.
                // Restart exactly once on this confirmed transition, without any wake timer.
                recoverAfterUnlock()
                return
            }
        }
        screen.updateLockState(state)
        clipboard.setSuspended(!connectionIntent.allowsControl || state != .unlocked || unlockPresented)
    }
    private func recoverAfterUnlock() {
        let id = generation
        let intent = connectionIntent
        recoveringVideo = true; hasVideo = false
        presenter?.stop(); displayLayer.flushAndRemoveImage()
        Task {
            // Allow the final key release/completion to finish before closing control.
            for _ in 0..<20 where unlockSending && generation == id {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard generation == id, phoneLockState == .unlocked else { return }
            let cleanup = disconnect()
            let next = generation
            recoveringVideo = true
            await cleanup?.value
            guard generation == next, phase == .idle else { return }
            connect(intent: intent)
        }
    }
    func connectWithPassword(_ password: String, method: UnlockInputMethod = .physical) {
        guard !authenticating, !unlockSending, canRequestUnlock else { return }
        guard UnlockKeyboard.supports(password), let account = credentialAccount else {
            error = L10n.tr("Use digits, English letters or symbols. Connect first if the device identity is not confirmed."); return
        }
        unlockAttempt = UnlockAttempt(account: account, password: password, method: method)
        scheduleUnlockExpiry()
        if connected {
            if phoneLockState == .locked { submitUnlock(password, method: method) }
            else if phoneLockState == .unlocked { clearUnlockAttempt(); dismissUnlock() }
        } else { connect() }
    }
    func useSavedPassword() {
        guard !authenticating, !unlockSending, canRequestUnlock, let account = credentialAccount else { return }
        authenticating = true; error = nil
        let selection = selectedID, id = generation
        Task {
            defer { authenticating = false }
            do {
                let password = try await credentials.readForAutofill(account, validity: preferences.authenticationMinutes * 60)
                guard generation == id, selectedID == selection, credentialAccount == account else { return }
                // Only this explicit button request grants an attempt. A cached Mac
                // authorization skips the system prompt, never the user's click.
                unlockAttempt = UnlockAttempt(account: account, password: password, method: preferences.unlockInputMethod)
                scheduleUnlockExpiry()
                if connected {
                    if phoneLockState == .locked { submitUnlock(password, method: preferences.unlockInputMethod) }
                    else if phoneLockState == .unlocked { clearUnlockAttempt(); dismissUnlock() }
                } else { connect() }
            } catch {
                guard generation == id else { return }
                if !Self.authenticationCancelled(error) { self.error = L10n.tr("Mac authentication was not completed. Try again.") }
            }
        }
    }
    private func scheduleUnlockExpiry() {
        unlockExpiryTask?.cancel()
        unlockExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }; self?.clearUnlockAttempt()
        }
    }
    private func clearUnlockAttempt() { unlockAttempt = nil; unlockExpiryTask?.cancel(); unlockExpiryTask = nil }
    static func authenticationCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return error is CancellationError || (nsError.domain == "com.apple.LocalAuthentication" && [-2, -3, -4, -9].contains(nsError.code))
    }
    func removeDevice(_ record: SavedDevice) async {
        do {
            if credentials.contains(record.id) { try await credentials.remove(record.id) }
            if selectedRecord?.id == record.id { await disconnect()?.value; selectedID = nil }
            registry.forget(record)
            if selectedID == nil { selectedID = registry.saved.first?.id }
        } catch { if !Self.authenticationCancelled(error) { self.error = L10n.tr("Could not delete the device. Try Mac authentication again.") } }
    }
    func connectPairedDevice(_ id: String) async {
        await disconnect()?.value
        while registry.refreshing { try? await Task.sleep(for: .milliseconds(50)) }
        try? await registry.allowDevice(id)
        await refresh(); selectedID = registry.device(for: id)?.id ?? id
        guard current?.ready == true else { error = L10n.tr("The device is not ready. Make sure Wireless debugging is still enabled."); return }
        connect()
    }
    func connectSaved(_ device: SavedDevice) async {
        await disconnect()?.value
        selectedID = device.id; pairingPresented = false
        // Return to the protected unlock entry; device selection does not read credentials.
    }
    @discardableResult
    func disconnect() -> Task<Void, Never>? {
        generation = UUID()
        unlockTask?.cancel(); unlockTask = nil
        clearUnlockAttempt(); recoveringVideo = false
        presenter?.stop(); presenter = nil
        lockMonitor.stop(); dismissUnlock()
        unlockSending = false; unlockMessage = nil; phoneLockState = .unknown; hasVideo = false
        clipboard.stop()
        let inputSession = unicodeInput; unicodeInput = nil
        typingTask?.cancel(); typingTask = nil
        let videoCleanup = session?.stop(restoreScreen: screen.detach())
        let cleanup: Task<Void, Never>? = videoCleanup == nil && inputSession == nil ? nil : Task {
            async let inputCleanup: Void = inputSession?.stop() ?? ()
            await videoCleanup?.value
            await inputCleanup
        }
        session = nil; phase = .idle
        connectionIntent = .standard
        displayLayer.flushAndRemoveImage()
        return cleanup
    }
    func configurationChanged() {
        guard phase != .idle else { return }
        let intent = connectionIntent
        let cleanup = disconnect(), id = generation
        Task {
            await cleanup?.value
            guard generation == id, phase == .idle else { return }
            connect(intent: intent)
        }
    }
    func mirrorDirectly() {
        guard !authenticating, !credentials.busy, !unlockSending, phase != .starting, hasSelection else { return }
        if connected && connectionIntent == .direct { return }
        let cleanup = disconnect(), id = generation
        connectionIntent = .direct
        Task {
            await cleanup?.value
            guard generation == id, phase == .idle else { return }
            connect(intent: .direct)
        }
    }
    func autoScreenOffChanged() {
        if canControl { screen.setAutoScreenOff(preferences.autoScreenOff) }
    }
    func input(_ command: Data) {
        guard acceptsPhoneInput else { return }
        session?.send(command)
    }
    func key(_ code: UInt32, modifiers: UInt32 = 0) {
        guard acceptsPhoneInput else { return }
        if unicodeInput != nil {
            let previous = typingTask, id = generation
            typingTask = Task {
                await previous?.value
                guard !Task.isCancelled, generation == id, phoneLockState == .unlocked else { return }
                session?.key(code, modifiers: modifiers)
            }
        } else { session?.key(code, modifiers: modifiers) }
    }
    func typeText(_ text: String) {
        guard canControl, phoneLockState == .unlocked, !unlockPresented, !text.isEmpty, let session else { return }
        let plainASCII = text.unicodeScalars.allSatisfy { (32...126).contains($0.value) } && text.utf8.count <= 300
        if plainASCII, unicodeInput == nil { session.send(ControlPacket.text(text)); return }
        if unicodeInput == nil { unicodeInput = UnicodeInputSession(device: session.device) }
        guard let input = unicodeInput else { return }
        let previous = typingTask, id = generation
        typingTask = Task {
            await previous?.value
            guard !Task.isCancelled, generation == id, phoneLockState == .unlocked else { return }
            do { try await input.commit(text) }
            catch {
                guard generation == id, !Task.isCancelled else { return }
                self.error = error is CancellationError ? nil : L10n.format("Text was not sent: %@", error.localizedDescription)
            }
        }
    }
    func paste(_ text: String? = nil) {
        guard canControl, phoneLockState != .locked, !unlockPresented else { return }; clipboard.paste(text)
    }
    func copy(cut: Bool = false) {
        guard canControl, phoneLockState != .locked, !unlockPresented else { return }; clipboard.copy(cut: cut)
    }
    func toggleScreen() { if canControl { screen.setPhysicalScreen(off: !screenOff) } }
    func wakePhone() {
        guard preferences.mode.allowsInput, connectionIntent.allowsControl else { return }
        if connected { screen.setPhysicalScreen(off: false); return }
        guard let device = current, device.ready else { return }
        Task {
            do { _ = try await adb.run(["-s", device.id, "shell", "input", "keyevent", "224"]) }
            catch { self.error = error.localizedDescription }
        }
    }
    func prepareUnlock() {
        guard connected, preferences.mode.allowsInput || isUSBConnection, phoneLockState != .unlocked, !unlockSending else { return }
        connectionIntent = .standard
        unlockPresented = true; unlockMessage = nil
        clipboard.setSuspended(true)
        // Present the Mac entry only. Device navigation belongs to the one-shot workflow.
    }
    func dismissUnlock() {
        unlockPresented = false
        clipboard.setSuspended(!connectionIntent.allowsControl || phoneLockState != .unlocked)
        if unlockKeyboardActive {
            session?.send(UnlockKeyboard.report()); session?.send(UnlockKeyboard.destroy())
            unlockKeyboardActive = false
        }
    }
    func submitUnlock(_ password: String, method: UnlockInputMethod) {
        guard connected, canRequestUnlock, phoneLockState == .locked, !unlockSending, let session else { return }
        guard UnlockKeyboard.supports(password) else {
            unlockMessage = L10n.tr("Use digits, English letters or symbols. Unlock patterns on your phone."); return
        }
        clearUnlockAttempt()
        prepareUnlock()
        unlockSending = true; unlockMessage = nil
        let id = generation
        unlockTask = Task {
            defer { if generation == id { unlockSending = false; unlockTask = nil } }
            do {
                typingTask?.cancel(); typingTask = nil
                let previousInput = unicodeInput; unicodeInput = nil
                await previousInput?.stop()
                try Task.checkCancellation()
                guard generation == id, phoneLockState == .locked else { return }
                screen.showForUnlock()
                let effectiveMethod = try await UnlockInputPreparation(adb: adb).prepare(
                    session: session, requested: method, keyboardAttached: unlockKeyboardActive,
                    onAttached: { [weak self] in
                        guard let self, self.generation == id else { return }
                        self.unlockKeyboardActive = true
                    }
                )
                try Task.checkCancellation()
                guard generation == id, phoneLockState == .locked else { return }
                unlockMessage = L10n.tr("Opening the phone password screen…")
                let ready = try await UnlockPreparation(adb: adb).prepare(device: session.device, videoSize: size)
                try Task.checkCancellation()
                guard generation == id, ready, phoneLockState == .locked else { return }
                unlockMessage = L10n.tr("Entering password…")
                let sent = await withCheckedContinuation { continuation in
                    session.submitUnlock(password, method: effectiveMethod) { continuation.resume(returning: $0) }
                }
                guard generation == id, !Task.isCancelled else { return }
                for _ in 0..<20 where phoneLockState == .locked {
                    try await Task.sleep(for: .milliseconds(150))
                }
                guard generation == id, phoneLockState == .locked else { return }
                credentials.clearAutofill()
                unlockMessage = sent ? L10n.tr("The phone is still locked. Check your password or choose Compatibility Input in Settings. Passwords are not retried automatically.") : L10n.tr("No password was sent. Check the connection.")
            } catch {
                guard generation == id, !Task.isCancelled else { return }
                credentials.clearAutofill()
                unlockMessage = error.localizedDescription
            }
        }
    }
    func capture() {
        guard let device = current, connected else { return }
        Task {
            do {
                let data = try await adb.data(["-s", device.id, "exec-out", "screencap", "-p"])
                guard NSImage(data: data) != nil else { throw MirrorError.message(L10n.tr("The phone did not return a valid screenshot.")) }
                let panel = NSSavePanel(); panel.allowedContentTypes = [.png]
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd-HHmmss"
                panel.nameFieldStringValue = "AndroidMirror-\(formatter.string(from: Date())).png"
                if await panel.begin() == .OK, let url = panel.url { try data.write(to: url) }
            } catch { self.error = error.localizedDescription }
        }
    }
}
