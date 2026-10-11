import Foundation

enum KeyguardStatus {
    enum Prompt: Equatable { case hidden, opening, ready, unknown }
    private static let scheduled = AndroidBooleanField(#"\b(?:isPrimaryBouncerShowingOrWillBeShowing|mPrimaryBouncerIsOrWillBeShowing)\s*[=:]\s*(true|false)\b"#)
    private static let primary = [
        AndroidBooleanField(#"\b(?:isPrimaryBouncerFullyShown|mPrimaryBouncerFullyShown)\s*[=:]\s*(true|false)\b"#),
        AndroidBooleanField(#"\b(?:mPrimaryBouncerShowing|isPrimaryBouncerShowing)\s*[=:]\s*(true|false)\b"#)
    ]
    private static let general = [
        AndroidBooleanField(#"\bisBouncerShowing\(\)\s*:\s*(true|false)\b"#),
        AndroidBooleanField(#"\b(?:mBouncerShowing|bouncerShowing)\s*[=:]\s*(true|false)\b"#),
        AndroidBooleanField(#"\bmBouncerVisible\s*[=:]\s*(true|false)\b"#)
    ]
    private static let alternate = AndroidBooleanField(#"\b(?:isAlternateBouncerShowing|mAlternateBouncerShowing)\s*[=:]\s*(true|false)\b"#)
    private static let fullyOn = AndroidBooleanField(#"\bmScreenOnFully\s*[=:]\s*(true|false)\b"#)
    private static let awake = AndroidBooleanField(#"\b(?:mAwake|mScreenOnFully|mScreenOn)\s*[=:]\s*(true|false)\b"#)

    static func prompt(_ output: String) -> Prompt {
        let future = scheduled.read(output)
        if future == .conflicting { return .unknown }
        for field in primary {
            switch field.read(output) {
            case .conflicting: return .unknown
            case .value(let shown): return shown ? .ready : (future == .value(true) ? .opening : .hidden)
            case .absent: continue
            }
        }
        if future == .value(false) { return .hidden }
        for field in general {
            switch field.read(output) {
            case .conflicting: return .unknown
            case .value(let shown):
                let biometric = alternate.read(output)
                if biometric == .conflicting { return .unknown }
                if shown, biometric != .value(true) { return .ready }
                return future == .value(true) ? .opening : .hidden
            case .absent: continue
            }
        }
        return future == .value(true) ? .opening : .unknown
    }
    static func screenAwake(_ output: String) -> Bool {
        let text = output.uppercased()
        if ["SCREEN_STATE_OFF", "SCREEN_STATE_TURNING_ON", "SCREEN_STATE_TURNING_OFF", "INTERACTIVE_STATE_SLEEP", "INTERACTIVE_STATE_GOING_TO_SLEEP"].contains(where: text.contains) { return false }
        if fullyOn.read(output) == .value(false) || fullyOn.read(output) == .conflicting { return false }
        return text.contains("SCREEN_STATE_ON") || text.contains("INTERACTIVE_STATE_AWAKE") || awake.read(output) == .value(true)
    }
}
