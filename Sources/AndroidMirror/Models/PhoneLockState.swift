import Foundation

enum PhoneLockState: Equatable {
    case unknown, locked, unlocked
    private static let fields = [
        AndroidBooleanField(#"\bmIsShowing\s*[=:]\s*(true|false)\b"#),
        AndroidBooleanField(#"\b(?:mKeyguardShowing|keyguardShowing|isKeyguardShowing|mShowingLockscreen)\s*[=:]\s*(true|false)\b"#),
        AndroidBooleanField(#"(?m)^\s*showing\s*[=:]\s*(true|false)\s*$"#)
    ]
    /// Never infer a lock from black video: protected apps can also be black.
    static func parse(_ policy: String) -> Self {
        for field in fields {
            switch field.read(policy) {
            case .value(let locked): return locked ? .locked : .unlocked
            case .conflicting: return .unknown
            case .absent: continue
            }
        }
        return .unknown
    }
}
