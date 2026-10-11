import Foundation

/// A temporary shell JAR uses Android's editable-node action; no installed app, IME or clipboard.
actor UnicodeInputSession {
    private let device: Device
    private let adb: any ADBTransport
    private var socket: LocalSocket?
    private var forward: String?
    private var remote: String?
    private var process: Process?
    private var stopped = false
    private var preparing = false

    init(device: Device, adb: any ADBTransport = ADBClient()) { self.device = device; self.adb = adb }
    private func run(_ args: [String], timeout: TimeInterval = 15) async throws -> String {
        try await adb.run(["-s", device.id] + args, timeout: timeout)
    }
    private func checkActive() throws { if stopped { throw CancellationError() } }
    static func packet(_ text: String) throws -> Data {
        let bytes = Data(text.utf8)
        guard !bytes.isEmpty, bytes.count <= 65536 else { throw MirrorError.message(L10n.tr("The text is too long. Enter it in smaller sections.")) }
        var data = Data(); data.put(UInt32(bytes.count)); data.append(bytes); return data
    }
    func commit(_ text: String) async throws {
        let packet = try Self.packet(text)
        try checkActive()
        if socket == nil { try await prepare() }
        try checkActive()
        guard let socket else { throw MirrorError.message(L10n.tr("The phone text service is not connected.")) }
        // Do not replay on failure: an input action might have completed before the socket timed out.
        do {
            try socket.write(packet)
            guard try socket.read(1).first == 1 else {
                throw MirrorError.message(L10n.tr("This field does not support direct Unicode input. Use the phone keyboard; copy and paste remain available."))
            }
        } catch {
            socket.shutdown(); self.socket = nil
            await cleanup()
            throw error
        }
    }
    private func prepare() async throws {
        preparing = true; defer { preparing = false }
        let capabilities = await AndroidCapabilities.detect(device: device, adb: adb)
        try checkActive()
        guard capabilities.supportsDirectText else {
            throw MirrorError.message(L10n.tr("Direct Unicode input requires Android 7.0 or later. Use the phone keyboard or paste manually."))
        }
        let currentUser = try await run(["shell", "am", "get-current-user"])
        guard currentUser == "0" else { throw MirrorError.message(L10n.tr("Direct Unicode input is currently supported only in the phone's main user profile.")) }
        guard let jar = AppResources.url(for: "android-mirror-text", extension: "jar"),
              let executable = ADBClient.executable else { throw MirrorError.message(L10n.tr("The phone text service is missing. Rebuild the app.")) }
        let token = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let path = "/data/local/tmp/lopleec-text-\(token).jar"
        _ = try await run(["push", jar.path, path]); remote = path
        try checkActive()
        let portText = try await run(["forward", "tcp:0", "localabstract:lopleec_text_\(token)"])
        forward = "tcp:" + portText
        guard let port = UInt16(portText) else { throw MirrorError.message(L10n.tr("Could not connect to the phone text service.")) }
        try checkActive()
        let service = Process(), output = Pipe()
        service.executableURL = executable
        service.arguments = ["-s", device.id, "shell", "CLASSPATH=\(path)", "app_process", "/",
                             "com.lopleec.androidmirror.text.TextServer", "lopleec_text_\(token)"]
        service.standardOutput = output; service.standardError = output
        // Drain process output without retaining editor contents, logging or surfacing stack traces.
        output.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        try service.run(); process = service
        for _ in 0..<100 {
            try checkActive()
            do {
                let candidate = try LocalSocket(port: port); candidate.timeout(4)
                guard try candidate.read(4).integer(at: 0, as: UInt32.self) == 0x414d5431 else { candidate.shutdown(); continue }
                socket = candidate; return
            } catch {
                if !service.isRunning { break }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        await cleanup()
        throw MirrorError.message(L10n.tr("Direct text input could not start. Use the phone keyboard or paste manually."))
    }
    func stop() async {
        stopped = true
        while preparing { try? await Task.sleep(for: .milliseconds(50)) }
        await cleanup()
    }
    private func cleanup() async {
        // A zero-length packet ends TextServer and releases its UiAutomation connection.
        // EOF alone makes the server accept another client instead of exiting.
        try? socket?.write(Data(repeating: 0, count: 4))
        socket?.shutdown(); socket = nil
        let service = process; process = nil
        if let service, service.isRunning {
            // Let UiAutomation disconnect naturally; terminate only if needed.
            for _ in 0..<10 where service.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
            if service.isRunning { service.terminate() }
        }
        if let forward { _ = try? await run(["forward", "--remove", forward]); self.forward = nil }
        if let remote { _ = try? await run(["shell", "rm", "-f", remote]); self.remote = nil }
    }
}
