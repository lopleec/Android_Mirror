import AVFoundation
import os

/// scrcpy raw audio: 48 kHz, two channels, signed 16-bit little-endian PCM.
enum PhonePCM {
    static let sampleRate = 48_000.0
    static func buffer(_ data: Data) -> AVAudioPCMBuffer? {
        guard !data.isEmpty, data.count % 4 == 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / 4)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = buffer.frameCapacity
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for frame in 0..<Int(buffer.frameLength) {
                for channel in 0..<2 {
                    let offset = frame * 4 + channel * 2
                    let signed = Int16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
                    channels[channel][frame] = Float(signed) / 32768
                }
            }
        }
        return buffer
    }
}

/// Called on the audio reader thread; stop is synchronized with playback and its completion callbacks.
final class AudioPlayback: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var pendingFrames = 0
    private var stopped = false
    private var completedFrames = 0
    private var receivedFrames = 0
    private var reportTime = ProcessInfo.processInfo.systemUptime
    private let logger = Logger(subsystem: "com.lopleec.androidmirror", category: "audio")
    init() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: PhonePCM.sampleRate, channels: 2, interleaved: false)!
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare(); try engine.start(); player.play()
    }
    func append(_ data: Data) throws {
        guard let buffer = PhonePCM.buffer(data) else { throw MirrorError.message(L10n.tr("Invalid phone audio data format.")) }
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        let frames = Int(buffer.frameLength)
        receivedFrames += frames
        // Bound playback to 100 ms. A burst cannot build seconds of stale sound.
        guard pendingFrames + frames <= 4_800 else { return }
        pendingFrames += frames
        // Track the player's render queue, excluding the output device's fixed latency.
        player.scheduleBuffer(buffer, completionCallbackType: .dataRendered) { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.pendingFrames = max(0, self.pendingFrames - frames); self.completedFrames += frames
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - reportTime >= 5 {
            logger.info("Audio received_frames=\(self.receivedFrames, privacy: .public) rendered_frames=\(self.completedFrames, privacy: .public) queued_ms=\(Double(self.pendingFrames) / 48, privacy: .public)")
            receivedFrames = 0; completedFrames = 0; reportTime = now
        }
    }
    func stop() {
        let shouldStop = lock.withLock { if stopped { return false }; stopped = true; pendingFrames = 0; return true }
        if shouldStop { player.stop(); engine.stop() }
    }
    deinit { stop() }
}
