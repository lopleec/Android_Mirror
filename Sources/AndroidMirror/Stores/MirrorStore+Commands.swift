import Foundation

extension MirrorStore {
    func addPhone() { disconnect(); pairingPresented = true }
    func isEnabled(_ action: PhoneAction) -> Bool {
        switch action {
        case .home, .recentApps, .notifications, .back: return acceptsPhoneInput
        case .screenshot, .rotate: return connected && phoneLockState == .unlocked && !unlockSending
        case .wake: return preferences.mode.allowsInput && current?.ready == true && !unlockSending && connectionIntent.allowsControl
        case .screenPower: return canControl && !unlockSending
        case .unlock: return connected && (preferences.mode.allowsInput || isUSBConnection) && phoneLockState == .locked && !unlockSending
        case .directMirror: return hasSelection && phase != .starting && !authenticating && !credentials.busy && !unlockSending
        }
    }
    func perform(_ action: PhoneAction) {
        guard isEnabled(action) else { return }
        switch action {
        case .home: key(3)
        case .recentApps: key(187)
        case .notifications: input(Data([5]))
        case .back: key(4)
        case .screenshot: capture()
        case .rotate: session?.send(Data([11]))
        case .wake: wakePhone()
        case .screenPower: toggleScreen()
        case .unlock: prepareUnlock()
        case .directMirror: mirrorDirectly()
        }
    }
}
