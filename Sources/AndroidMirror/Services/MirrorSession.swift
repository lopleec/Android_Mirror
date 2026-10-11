import Foundation
import CoreMedia

final class MirrorSession: @unchecked Sendable {
    let device: Device
    private let adb = ADBClient()
    private let lock = NSLock()
    private var stopped = false
    private var video: LocalSocket?
    private var control: LocalSocket?
    private var audio: LocalSocket?
    private var audioPlayer: AudioPlayback?
    private var process: Process?
    private var forward: String?
    private var remotePath: String?
    private let writer = DispatchQueue(label: "com.lopleec.androidmirror.control")
    private var log = ""
    var onFrame: ((CMSampleBuffer, CGSize) -> Void)?
    var onClipboard: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onAudioWarning: ((String) -> Void)?

    init(device: Device) { self.device = device }
    private var isStopped: Bool { lock.withLock { stopped } }

    func start(configuration: MirrorConfiguration) async throws {
        let capabilities = await AndroidCapabilities.detect(device: device, adb: adb)
        guard !isStopped else { throw CancellationError() }
        guard capabilities.supportsMirroring else {
            throw MirrorError.message(L10n.tr("Screen mirroring requires Android 5.0 or later."))
        }
        // The server options and socket sequence must use the same negotiated features.
        let effective = capabilities.configuration(for: configuration)
        if configuration.audioEnabled && !effective.audioEnabled {
            onAudioWarning?(L10n.tr("Mac audio requires Android 11 or later. Video mirroring remains available."))
        }
        guard let server = AppResources.url(for: "scrcpy-server") else {
            throw MirrorError.message(L10n.tr("The mirroring server is missing. Rebuild the app."))
        }
        // This is a temporary shell service, never an APK install into any Android user/profile.
        let scid = String(format: "%08x", UInt32.random(in: 1...0x7fff_ffff))
        let remote = "/data/local/tmp/lopleec-mirror-\(scid).jar"
        _ = try await adb.run(["-s", device.id, "push", server.path, remote])
        lock.withLock { remotePath = remote }
        guard !isStopped else { await removeRemote(); throw CancellationError() }
        let portText = try await adb.run(["-s", device.id, "forward", "tcp:0", "localabstract:scrcpy_\(scid)"])
        guard let port = UInt16(portText) else { throw MirrorError.message(L10n.tr("Could not allocate a mirroring port.")) }
        lock.withLock { forward = "tcp:\(port)" }
        guard !isStopped else { await removeForward(); throw CancellationError() }
        guard let executable = ADBClient.executable else { throw MirrorError.message(L10n.tr("ADB is unavailable.")) }
        let serverProcess = Process()
        let pipe = Pipe()
        serverProcess.executableURL = executable
        serverProcess.arguments = ["-s", device.id, "shell", "CLASSPATH=\(remote)", "app_process", "/",
            "com.genymobile.scrcpy.Server"] + effective.serverArguments(scid: scid)
        serverProcess.standardOutput = pipe; serverProcess.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard let self, !bytes.isEmpty else { handle.readabilityHandler = nil; return }
            self.lock.withLock { self.log = String((self.log + String(decoding: bytes, as: UTF8.self)).suffix(3000)) }
        }
        try serverProcess.run()
        lock.withLock { process = serverProcess }
        guard !isStopped else { serverProcess.terminate(); throw CancellationError() }
        try await Task.detached(priority: .userInitiated) { [self] in
            var socket: LocalSocket?
            for _ in 0..<50 {
                guard !isStopped else { throw CancellationError() }
                do {
                    let candidate = try LocalSocket(port: port)
                    candidate.timeout(1)
                    guard try candidate.read(1).first == 0 else { continue }
                    socket = candidate; break
                } catch { try await Task.sleep(for: .milliseconds(100)) }
            }
            guard let socket else {
                let details = lock.withLock { log }
                throw MirrorError.message(L10n.format("The phone mirroring service could not start.\n%@", details.isEmpty ? L10n.tr("Make sure your phone is unlocked and debugging is allowed.") : details))
            }
            socket.timeout(0)
            let audioSocket = effective.audioEnabled ? try LocalSocket(port: port) : nil
            audioSocket?.timeout(0)
            let controlSocket = try LocalSocket(port: port)
            controlSocket.timeout(5)
            let cancelled = lock.withLock {
                if stopped { return true }
                video = socket; audio = audioSocket; control = controlSocket; return false
            }
            if cancelled { socket.shutdown(); audioSocket?.shutdown(); controlSocket.shutdown(); throw CancellationError() }
            DispatchQueue.global(qos: .userInteractive).async { [self] in readVideo(socket) }
            if let audioSocket { DispatchQueue.global(qos: .userInitiated).async { [self] in readAudio(audioSocket) } }
            DispatchQueue.global(qos: .userInitiated).async { [self] in readControl(controlSocket) }
        }.value
    }

    private func readVideo(_ socket: LocalSocket) {
        do {
            let metadata = try socket.read(12)
            guard metadata.integer(at: 0, as: UInt32.self) == 0x68323634 else { throw MirrorError.message(L10n.tr("The device did not return an H.264 video stream.")) }
            let decoder = H264Decoder()
            let hardware = HardwareVideoDecoder()
            while !isStopped {
                let header = try socket.read(12)
                let flags: UInt64 = header.integer(at: 0)
                let size: UInt32 = header.integer(at: 8)
                let packet = try socket.read(Int(size))
                if let sample = try decoder.consume(packet, pts: flags & 0x3fff_ffff_ffff_ffff), let format = decoder.format {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                    if let image = try hardware.decode(sample) {
                        onFrame?(image, CGSize(width: Int(dimensions.width), height: Int(dimensions.height)))
                    }
                }
            }
        } catch { fail(error) }
    }
    private func readControl(_ socket: LocalSocket) {
        socket.readTimeout(0)
        do {
            while !isStopped {
                let type = try socket.read(1)[0]
                switch type {
                case 0:
                    let length = try socket.read(4).integer(at: 0, as: UInt32.self)
                    guard length <= 262139 else { throw MirrorError.message(L10n.tr("Invalid clipboard data length.")) }
                    let text = String(decoding: try socket.read(Int(length)), as: UTF8.self)
                    onClipboard?(text)
                case 1: _ = try socket.read(8) // clipboard acknowledgement
                case 2:
                    let header = try socket.read(4)
                    _ = try socket.read(Int(header.integer(at: 2, as: UInt16.self)))
                default: throw MirrorError.message(L10n.tr("Received an unknown device control message."))
                }
            }
        } catch { fail(error) }
    }
    private func readAudio(_ socket: LocalSocket) {
        do {
            let codec: UInt32 = try socket.read(4).integer(at: 0)
            guard codec > 1 else {
                if !isStopped { onAudioWarning?(L10n.tr("Phone audio is unavailable. Unlock and reconnect, or select Phone Speaker.")) }
                return
            }
            guard codec == 0x00726177 else { throw MirrorError.message(L10n.tr("The phone did not return PCM audio.")) }
            let playback = try AudioPlayback()
            let cancelled = lock.withLock { if stopped { return true }; audioPlayer = playback; return false }
            guard !cancelled else { playback.stop(); return }
            defer { playback.stop() }
            while !isStopped {
                let header = try socket.read(12)
                let flags: UInt64 = header.integer(at: 0)
                let length: UInt32 = header.integer(at: 8)
                guard length <= 192_000 else { throw MirrorError.message(L10n.tr("Invalid phone audio packet length.")) }
                let bytes = try socket.read(Int(length))
                if flags & (UInt64(1) << 63) == 0 { try playback.append(bytes) }
            }
        } catch { if !isStopped { onAudioWarning?(L10n.format("Audio playback paused: %@", error.localizedDescription)) } }
    }
    private func fail(_ error: Error) { if !isStopped { onError?(error.localizedDescription); stop() } }
    func send(_ data: Data) {
        writer.async { [weak self] in
            guard let self, !self.isStopped else { return }
            let socket = self.lock.withLock { self.control }
            do { try socket?.write(data) } catch { self.fail(error) }
        }
    }
    func key(_ code: UInt32, modifiers: UInt32 = 0) {
        send(ControlPacket.key(code, down: true, modifiers: modifiers))
        send(ControlPacket.key(code, down: false, modifiers: modifiers))
    }
    func openUnlockKeyboard() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.async { [weak self] in
                guard let self, !self.isStopped, let socket = self.lock.withLock({ self.control }) else {
                    continuation.resume(throwing: CancellationError()); return
                }
                do {
                    try socket.write(UnlockKeyboard.create())
                    // Keyboard attachment can rebuild keyguard. Finish it before navigating.
                    Thread.sleep(forTimeInterval: 0.5)
                    continuation.resume()
                } catch { continuation.resume(throwing: error); self.fail(error) }
            }
        }
    }
    func submitUnlock(_ password: String, method: UnlockInputMethod, completion: @escaping (Bool) -> Void) {
        guard UnlockKeyboard.supports(password), let strokes = UnlockKeyboard.strokes(for: password) else { completion(false); return }
        let packets = method == .physical ? strokes : [ControlPacket.text(password),
            ControlPacket.key(66, down: true), ControlPacket.key(66, down: false)]
        writer.async { [weak self] in
            guard let self, !self.isStopped, let socket = self.lock.withLock({ self.control }) else { completion(false); return }
            do {
                for packet in packets {
                    guard !self.isStopped else { completion(false); return }
                    try socket.write(packet)
                    Thread.sleep(forTimeInterval: 0.02)
                }
                completion(true)
            } catch { completion(false); self.fail(error) }
        }
    }
    @discardableResult
    func stop(restoreScreen: Bool = false) -> Task<Void, Never> {
        let resources = lock.withLock { () -> (LocalSocket?, LocalSocket?, LocalSocket?, AudioPlayback?, Process?, String?, String?)? in
            guard !stopped else { return nil }
            stopped = true
            let resources = (video, control, audio, audioPlayer, process, forward, remotePath)
            video = nil; control = nil; audio = nil; audioPlayer = nil; process = nil; forward = nil; remotePath = nil
            return resources
        }
        guard let (video, control, audio, audioPlayer, process, forward, remote) = resources else { return Task {} }
        // Capture resources, never self: cleanup remains valid after the session is released.
        let writer = writer, adb = adb, device = device
        return Task {
            await withCheckedContinuation { continuation in
                writer.async {
                    if restoreScreen {
                        // Restore before closing video: closing it can terminate the Android controller.
                        try? control?.write(ScreenCommand.display(on: true))
                    }
                    video?.shutdown(); control?.shutdown(); audio?.shutdown(); audioPlayer?.stop()
                    continuation.resume()
                }
            }
            // Let the server close naturally and restore settings before another session starts.
            if let process, process.isRunning {
                let watchdog = Task {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled && process.isRunning { process.terminate() }
                }
                await Task.detached { process.waitUntilExit() }.value
                watchdog.cancel()
            }
            if let forward { _ = try? await adb.run(["-s", device.id, "forward", "--remove", forward]) }
            if let remote { _ = try? await adb.run(["-s", device.id, "shell", "rm", "-f", remote]) }
        }
    }
    private func removeForward() async {
        let value = lock.withLock { let value = forward; forward = nil; return value }
        if let value { _ = try? await adb.run(["-s", device.id, "forward", "--remove", value]) }
    }
    private func removeRemote() async {
        let value = lock.withLock { let value = remotePath; remotePath = nil; return value }
        if let value { _ = try? await adb.run(["-s", device.id, "shell", "rm", "-f", value]) }
    }
    deinit { stop() }
}
