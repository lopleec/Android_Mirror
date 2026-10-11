import Foundation

/// A read-only status poll. It never sends a wake, sleep, or unlock command.
@MainActor
final class PhoneLockMonitor {
    private let adb: any ADBTransport
    private var task: Task<Void, Never>?
    init(adb: any ADBTransport = ADBClient()) { self.adb = adb }
    func start(device: Device, onChange: @escaping (PhoneLockState) -> Void) {
        stop()
        let adb = adb
        task = Task {
            var previous: PhoneLockState?
            while !Task.isCancelled {
                let output = try? await adb.run(["-s", device.id, "shell", "dumpsys", "window", "policy"], timeout: 4)
                guard !Task.isCancelled else { return }
                let state = output.map(PhoneLockState.parse) ?? .unknown
                // An unavailable poll must not dismiss a confirmed lock screen into black video.
                if state != .unknown || previous == nil {
                    if state != previous { previous = state; onChange(state) }
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
    deinit { task?.cancel() }
}
