import Foundation

/// Gate optional features by platform capabilities instead of manufacturer/model names.
struct AndroidCapabilities: Equatable {
    let sdk: Int?
    init(sdkOutput: String) {
        let value = Int(sdkOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        sdk = value.flatMap { $0 > 0 ? $0 : nil }
    }
    var supportsMirroring: Bool { sdk.map { $0 >= 21 } ?? true }
    var supportsAudio: Bool { sdk.map { $0 >= 30 } ?? true }
    var supportsDirectText: Bool { sdk.map { $0 >= 24 } ?? true }
    func configuration(for requested: MirrorConfiguration) -> MirrorConfiguration {
        MirrorConfiguration(maxSize: requested.maxSize, keepAwake: requested.keepAwake,
                            powerOn: requested.powerOn, audioEnabled: requested.audioEnabled && supportsAudio)
    }
    static func detect(device: Device, adb: any ADBTransport) async -> Self {
        let value = try? await adb.run(["-s", device.id, "shell", "getprop", "ro.build.version.sdk"], timeout: 4)
        return Self(sdkOutput: value ?? "")
    }
}
