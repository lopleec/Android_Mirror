import Foundation

struct KeyguardPromptNavigator {
    let adb: any ADBTransport
    func prepare(_ device: Device) async -> Bool {
        guard let jar = AppResources.url(for: "android-mirror-text", extension: "jar") else { return false }
        let path = "/data/local/tmp/lopleec-keyguard-\(UUID().uuidString).jar"
        let prefix = ["-s", device.id]
        var ready = false
        do {
            _ = try await adb.run(prefix + ["push", jar.path, path], timeout: 4)
            try Task.checkCancellation()
            let result = try await adb.run(prefix + ["shell", "CLASSPATH=\(path)", "app_process", "/", "com.lopleec.androidmirror.text.KeyguardPrompt"], timeout: 5)
            ready = result.split(separator: "\n").contains { $0 == "MIRROR_KEYGUARD:READY" || $0 == "MIRROR_KEYGUARD:VISIBLE" }
        } catch { }
        _ = try? await adb.run(prefix + ["shell", "rm", "-f", path], timeout: 4)
        return ready
    }
}
