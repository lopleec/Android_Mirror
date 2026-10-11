import Foundation

/// Session-scoped intent: direct mirroring never reads a credential or drives the lock screen.
enum MirrorConnectionIntent {
    case standard, direct
    var allowsControl: Bool { self == .standard }
    func configuration(from requested: MirrorConfiguration) -> MirrorConfiguration {
        guard self == .direct else { return requested }
        return MirrorConfiguration(maxSize: requested.maxSize, keepAwake: false, powerOn: false,
            audioEnabled: requested.audioEnabled, videoQuality: requested.videoQuality)
    }
    func showsUnlock(state: PhoneLockState, requested: Bool) -> Bool {
        self == .standard && (state == .locked || requested)
    }
    func waitsForLockState(_ state: PhoneLockState) -> Bool {
        self == .standard && state == .unknown
    }
}
