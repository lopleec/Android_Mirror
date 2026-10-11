import Foundation

struct MirrorConfiguration: Equatable {
    static let serverVersion = "3.3.4"
    let maxSize: Int
    let keepAwake: Bool
    let powerOn: Bool
    let audioEnabled: Bool

    init(maxSize: Int, keepAwake: Bool, powerOn: Bool, audioEnabled: Bool = true) {
        self.maxSize = maxSize; self.keepAwake = keepAwake; self.powerOn = powerOn; self.audioEnabled = audioEnabled
    }

    func serverArguments(scid: String) -> [String] {
        var options = [Self.serverVersion, "scid=\(scid)", "tunnel_forward=true", "audio=\(audioEnabled)",
            "audio_codec=raw", "audio_source=output",
            "video_codec=h264", "max_size=\(maxSize)",
            "video_bit_rate=\(maxSize == 1280 ? 4_000_000 : 8_000_000)", "max_fps=60",
            "send_device_meta=false", "clipboard_autosync=true", "log_level=warn", "cleanup=true",
            "power_on=\(powerOn)"]
        // Milliseconds, not seconds. Unlike stay_awake, this works on unplugged Wi-Fi devices.
        // scrcpy's device-side cleanup restores the original timeout even on connection loss.
        if keepAwake { options.append("screen_off_timeout=\(Int32.max)") }
        return options
    }
}

enum ScreenCommand {
    /// WAKEUP is idempotent. POWER would accidentally put an already-awake device to sleep.
    static func wake(showPhysicalScreen: Bool) -> [Data] {
        [Data([10, showPhysicalScreen ? 1 : 0]),
         ControlPacket.key(224, down: true), ControlPacket.key(224, down: false)]
    }
    static func display(on: Bool) -> Data { Data([10, on ? 1 : 0]) }
}
