import Foundation

struct ADBClient: ADBTransport {
    static let downloadURL = URL(string: "https://developer.android.com/tools/releases/platform-tools#downloads")!
    static var executable: URL? {
        let custom = UserDefaults.standard.string(forKey: "adbPath") ?? ""
        let candidates = [custom,
            Bundle.main.resourceURL?.appendingPathComponent("Tools/adb").path ?? "",
            "/opt/homebrew/bin/adb", "/usr/local/bin/adb",
            NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
            NSHomeDirectory() + "/Documents/Android/platform-tools/adb"]
        return candidates.first(where: { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    func run(_ arguments: [String], timeout: TimeInterval = 15) async throws -> String {
        String(decoding: try await data(arguments, timeout: timeout), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func data(_ arguments: [String], timeout: TimeInterval = 15) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let executable = Self.executable else { throw MirrorError.message(L10n.tr("ADB was not found. Choose the adb executable from Android Platform-Tools in Settings.")) }
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            var environment = ProcessInfo.processInfo.environment
            environment["ADB_MDNS_OPENSCREEN"] = "1"
            process.environment = environment
            try process.run()
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { if process.isRunning { process.terminate() } }
            timer.resume()
            let bytes = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timer.cancel()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw MirrorError.message(message.isEmpty ? L10n.tr("The ADB operation timed out. Check the phone connection.") : message)
            }
            return bytes
        }.value
    }

    func devices() async throws -> [Device] { Device.parse(try await run(["devices", "-l"])) }
    func services() async throws -> [WirelessService] { WirelessService.parse(try await run(["mdns", "services"])) }
    func pair(endpoint: String, code: String) async throws {
        guard Endpoint.valid(endpoint), !code.isEmpty else { throw MirrorError.message(L10n.tr("Enter a valid IP address and pairing port.")) }
        let result = try await run(["pair", endpoint, code], timeout: 35)
        guard result.lowercased().contains("successfully paired") else { throw MirrorError.message(result) }
    }
    func connect(_ endpoint: String) async throws {
        guard Endpoint.valid(endpoint) else { throw MirrorError.message(L10n.tr("Use an IP:port address, such as 192.168.1.8:37123.")) }
        let result = try await run(["connect", endpoint])
        guard result.contains("connected to") else { throw MirrorError.message(result) }
    }
}
