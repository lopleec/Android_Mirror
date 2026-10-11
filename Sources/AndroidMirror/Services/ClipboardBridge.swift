import AppKit

@MainActor
final class ClipboardBridge {
    private let preferences: MirrorPreferences
    private weak var session: MirrorSession?
    private var timer: Timer?
    private var changeCount = NSPasteboard.general.changeCount
    private var lastText = ""
    private var manualCopyUntil = Date.distantPast
    private var suspended = false

    init(preferences: MirrorPreferences) { self.preferences = preferences }
    func attach(_ session: MirrorSession, suspended: Bool = false) {
        stop(); self.session = session
        self.suspended = suspended
        changeCount = NSPasteboard.general.changeCount
        if !suspended && preferences.mode.allowsInput && preferences.clipboardSync { session.send(Data([8, 0])) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncToPhone() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil; session = nil; manualCopyUntil = .distantPast; lastText = "" }
    func setSuspended(_ suspended: Bool) {
        guard self.suspended != suspended else { return }
        self.suspended = suspended; changeCount = NSPasteboard.general.changeCount
        manualCopyUntil = .distantPast
        if !suspended, preferences.mode.allowsInput, preferences.clipboardSync { session?.send(Data([8, 0])) }
    }
    func receive(_ text: String) {
        guard !suspended, session != nil, preferences.mode.allowsInput,
              preferences.clipboardSync || Date() < manualCopyUntil else { return }
        manualCopyUntil = .distantPast; lastText = text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        changeCount = NSPasteboard.general.changeCount
    }
    func paste(_ text: String? = nil) {
        guard !suspended, preferences.mode.allowsInput, let text = text ?? NSPasteboard.general.string(forType: .string) else { return }
        lastText = text; session?.send(ControlPacket.clipboard(text, paste: true))
    }
    func copy(cut: Bool) {
        guard !suspended, preferences.mode.allowsInput else { return }
        manualCopyUntil = Date().addingTimeInterval(3)
        session?.send(Data([8, cut ? 2 : 1]))
    }
    private func syncToPhone() {
        guard !suspended, session != nil, preferences.mode.allowsInput, preferences.clipboardSync else {
            changeCount = NSPasteboard.general.changeCount; return
        }
        let board = NSPasteboard.general
        guard board.changeCount != changeCount else { return }
        changeCount = board.changeCount
        guard let text = board.string(forType: .string), text != lastText else { return }
        lastText = text; session?.send(ControlPacket.clipboard(text, paste: false))
    }
}
