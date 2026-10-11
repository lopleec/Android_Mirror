import Foundation

protocol UnlockKeyboardTransport: AnyObject, Sendable {
    var device: Device { get }
    func openUnlockKeyboard() async throws
}
extension MirrorSession: UnlockKeyboardTransport {}

/// Prepare the chosen keyboard before keyguard navigation. Credentials are never part of this service.
struct UnlockInputPreparation {
    let adb: any ADBTransport
    func prepare(session: any UnlockKeyboardTransport, requested: UnlockInputMethod, keyboardAttached: Bool,
                 onAttached: @MainActor @Sendable () -> Void) async throws -> UnlockInputMethod {
        try Task.checkCancellation()
        guard requested == .physical else { return .compatibility }
        do {
            _ = try await adb.run(["-s", session.device.id, "shell", "test", "-r", "/dev/uhid", "-a", "-w", "/dev/uhid"], timeout: 4)
        } catch {
            try Task.checkCancellation()
            return .compatibility
        }
        try Task.checkCancellation()
        if !keyboardAttached {
            try await session.openUnlockKeyboard()
            await onAttached()
        }
        try Task.checkCancellation()
        return .physical
    }
}
