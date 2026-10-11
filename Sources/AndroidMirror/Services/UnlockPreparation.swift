import Foundation

/// Only navigates to keyguard's credential prompt. No credential is passed to ADB.
struct UnlockPreparation {
    let adb: any ADBTransport
    var pause: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func prepare(device: Device, videoSize: CGSize) async throws -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        let prefix = ["-s", device.id, "shell"]
        @Sendable func policy() async throws -> String { try await adb.run(prefix + ["dumpsys", "window", "policy"], timeout: 4) }
        @Sendable func prompt() async -> PromptState {
            guard let output = try? await adb.run(prefix + ["dumpsys", "activity", "service", "com.android.systemui/.SystemUIService"], timeout: 4) else { return .unknown }
            return Self.promptState(output)
        }
        let initial = try await policy()
        if PhoneLockState.parse(initial) == .unlocked { return false }
        if !Self.screenAwake(initial) {
            _ = try await adb.run(prefix + ["input", "keyevent", "224"], timeout: 4)
            var awake = false
            for _ in 0..<20 {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                let output = try await policy()
                if PhoneLockState.parse(output) == .unlocked { return false }
                if Self.screenAwake(output) { awake = true; break }
                try await pause(.milliseconds(80))
            }
            guard awake else { throw MirrorError.message(L10n.tr("The phone screen is not ready. Turn it on and try again.")) }
            try await pause(.milliseconds(100))
        }
        // Cache gesture geometry for this request. Retry navigation only, never credentials.
        async let dimensions = try? adb.run(prefix + ["wm", "size"], timeout: 4)
        async let viewport = try? adb.run(prefix + ["dumpsys", "input"], timeout: 4)
        async let firstPrompt = prompt()
        let (dimensionOutput, viewportOutput, initialPrompt) = await (dimensions, viewport, firstPrompt)
        var navigationCount = 0
        func swipe() async throws {
            let size = try viewportOutput.flatMap(AndroidDisplayGeometry.primaryViewport) ?? Self.screenSize(dimensionOutput ?? "", orientation: videoSize)
            let x = String(Int(size.width * 0.25)) // Away from under-display fingerprint.
            _ = try await adb.run(prefix + ["input", "swipe", x, String(Int(size.height * 0.92)), x,
                                           String(Int(size.height * 0.30)), "220"], timeout: 4)
            navigationCount += 1
            try await pause(.milliseconds(120))
        }
        if initialPrompt == .hidden || initialPrompt == .unknown { try await swipe() }
        var consecutiveReady = 0, hiddenPolls = 0, triedEditorFallback = false
        for attempt in 0..<24 {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            async let currentPolicy = policy()
            async let currentPrompt = prompt()
            let (output, visible) = try await (currentPolicy, currentPrompt)
            switch PhoneLockState.parse(output) {
            case .unlocked: return false // User/face unlock won the race: never type into an app.
            case .unknown: consecutiveReady = 0
            case .locked:
                if Self.screenAwake(output), visible == .ready { consecutiveReady += 1 }
                else { consecutiveReady = 0 }
                // Older/vendor SystemUI may not report its primary panel. Only then
                // start the temporary focus helper, once. Normal unlock skips its
                // push, VM startup and accessibility idle wait entirely.
                if Self.screenAwake(output), visible == .unknown, attempt >= 1, !triedEditorFallback {
                    triedEditorFallback = true
                    let editorVisible = await KeyguardPromptNavigator(adb: adb).prepare(device)
                    let finalPrompt = await prompt()
                    let final = try await policy()
                    if PhoneLockState.parse(final) == .unlocked { return false }
                    if editorVisible, finalPrompt != .hidden, PhoneLockState.parse(final) == .locked,
                       Self.screenAwake(final) { return true }
                }
            }
            // A first gesture may be consumed by wake/keyguard initialization even
            // after the display reports ON. Act on confirmed state instead of waiting
            // until this whole request fails and requiring a second user click.
            if PhoneLockState.parse(output) == .locked, Self.screenAwake(output), visible == .hidden {
                hiddenPolls += 1
            } else { hiddenPolls = 0 }
            if hiddenPolls >= 3, navigationCount < 3 {
                let finalPrompt = await prompt()
                let final = try await policy()
                if PhoneLockState.parse(final) == .unlocked { return false }
                if finalPrompt == .hidden, PhoneLockState.parse(final) == .locked, Self.screenAwake(final) {
                    try Task.checkCancellation()
                    try await swipe()
                    hiddenPolls = 0; consecutiveReady = 0
                    continue
                }
            }
            if consecutiveReady >= 2 {
                // Fresh lock check immediately before returning authorization to type.
                // Do not launch a second helper or add a fixed post-ready delay.
                let final = try await policy()
                if PhoneLockState.parse(final) == .unlocked { return false }
                if PhoneLockState.parse(final) == .locked, Self.screenAwake(final) { return true }
                consecutiveReady = 0
            }
            try await pause(.milliseconds(80))
        }
        throw MirrorError.message(L10n.tr("Could not confirm the phone password screen. Open it on your phone and try again. No password was sent."))
    }

    typealias PromptState = KeyguardStatus.Prompt
    static func promptVisible(_ output: String) -> Bool? {
        switch promptState(output) {
        case .ready: return true
        case .hidden: return false
        case .opening, .unknown: return nil
        }
    }
    static func promptState(_ output: String) -> PromptState { KeyguardStatus.prompt(output) }
    static func screenAwake(_ output: String) -> Bool { KeyguardStatus.screenAwake(output) }
    static func screenSize(_ output: String, orientation: CGSize) throws -> CGSize {
        try AndroidDisplayGeometry.screenSize(output, orientation: orientation)
    }
}
