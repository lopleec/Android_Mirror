import Foundation
import Observation

enum InteractionMode: String, CaseIterable, Identifiable {
    case control, viewOnly
    var id: String { rawValue }
    var title: String { self == .control ? L10n.tr("Control Phone") : L10n.tr("View Only") }
    var allowsInput: Bool { self == .control }
}

/// The single source of truth for preferences. Inject isolated defaults in tests.
@MainActor @Observable
final class MirrorPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    var mode: InteractionMode { didSet { defaults.set(mode.rawValue, forKey: "interactionMode") } }
    var keepAwake: Bool { didSet { defaults.set(keepAwake, forKey: "keepAwake") } }
    var autoScreenOff: Bool { didSet { defaults.set(autoScreenOff, forKey: "autoScreenOff") } }
    var clipboardSync: Bool { didSet { defaults.set(clipboardSync, forKey: "clipboardSync") } }
    var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    var autoReconnect: Bool { didSet { defaults.set(autoReconnect, forKey: "autoReconnect") } }
    var maxSize: Int { didSet { defaults.set(maxSize, forKey: "maxSize") } }
    var adbPath: String { didSet { defaults.set(adbPath, forKey: "adbPath") } }
    var unlockInputMethod: UnlockInputMethod { didSet { defaults.set(unlockInputMethod.rawValue, forKey: "unlockInputMethod") } }
    var authenticationMinutes: Double { didSet { defaults.set(authenticationMinutes, forKey: "authenticationMinutes") } }
    var audioOutput: AudioOutput { didSet { defaults.set(audioOutput.rawValue, forKey: "audioOutput") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = InteractionMode(rawValue: defaults.string(forKey: "interactionMode") ?? "") ?? .control
        keepAwake = defaults.object(forKey: "keepAwake") as? Bool ?? true
        autoScreenOff = defaults.bool(forKey: "autoScreenOff")
        clipboardSync = defaults.object(forKey: "clipboardSync") as? Bool ?? true
        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        autoReconnect = defaults.object(forKey: "autoReconnect") as? Bool ?? true
        maxSize = defaults.object(forKey: "maxSize") as? Int ?? 1920
        adbPath = defaults.string(forKey: "adbPath") ?? ""
        unlockInputMethod = UnlockInputMethod(rawValue: defaults.string(forKey: "unlockInputMethod") ?? "") ?? .physical
        authenticationMinutes = min(30, max(0, defaults.object(forKey: "authenticationMinutes") as? Double ?? 10))
        audioOutput = AudioOutput(rawValue: defaults.string(forKey: "audioOutput") ?? "") ?? .computer
    }
    var configuration: MirrorConfiguration {
        MirrorConfiguration(maxSize: maxSize, keepAwake: mode.allowsInput && keepAwake,
                            powerOn: mode.allowsInput, audioEnabled: audioOutput == .computer)
    }
}
