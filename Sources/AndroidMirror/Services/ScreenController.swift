import Foundation
import Observation

protocol ScreenTransport: AnyObject { func send(_ command: Data) }
extension MirrorSession: ScreenTransport {}

/// Physical display power and Android wakefulness are different states.
@MainActor @Observable
final class ScreenController {
    private(set) var physicalScreenOff = false
    @ObservationIgnored private weak var transport: (any ScreenTransport)?
    @ObservationIgnored private let preferences: MirrorPreferences
    private var autoScreenOff = false
    private var lockState: PhoneLockState = .unknown

    init(preferences: MirrorPreferences) { self.preferences = preferences }
    func attach(_ transport: any ScreenTransport, autoScreenOff: Bool) {
        self.transport = transport; physicalScreenOff = false
        self.autoScreenOff = autoScreenOff; lockState = .unknown
    }
    func detach() -> Bool {
        let restore = physicalScreenOff
        transport = nil; physicalScreenOff = false; autoScreenOff = false; lockState = .unknown
        return restore
    }
    func setPhysicalScreen(off: Bool) {
        guard let transport else { return }
        physicalScreenOff = off
        if off {
            // Display power alone does not wake Android or trigger scrcpy's delayed power-off.
            transport.send(ScreenCommand.display(on: false))
        } else {
            ScreenCommand.wake(showPhysicalScreen: true).forEach(transport.send)
        }
    }
    /// The unlock workflow awaits its own idempotent WAKEUP via ADB.
    func showForUnlock() {
        guard let transport else { return }
        physicalScreenOff = false
        transport.send(ScreenCommand.display(on: true))
    }
    func updateLockState(_ state: PhoneLockState) {
        lockState = state
        applyAutoScreenOff()
    }
    func setAutoScreenOff(_ enabled: Bool) {
        autoScreenOff = enabled
        if enabled { applyAutoScreenOff() }
        else if physicalScreenOff { setPhysicalScreen(off: false) }
    }
    private func applyAutoScreenOff() {
        guard preferences.mode.allowsInput, autoScreenOff, lockState == .unlocked, !physicalScreenOff else { return }
        setPhysicalScreen(off: true)
    }
}
