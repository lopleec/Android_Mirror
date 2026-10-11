import SwiftUI
import AppKit

struct WindowPreferences: NSViewRepresentable {
    let alwaysOnTop: Bool
    let videoSize: CGSize?
    func makeNSView(context: Context) -> MirrorWindowView { MirrorWindowView() }
    func updateNSView(_ view: MirrorWindowView, context: Context) {
        view.alwaysOnTop = alwaysOnTop
        view.videoSize = videoSize
        DispatchQueue.main.async { view.configure() }
    }
}

final class MirrorWindowView: NSView {
    var alwaysOnTop = false
    var videoSize: CGSize?
    private var configured = false
    private var previousVideoSize: CGSize?
    private let resizeDelegate = ProportionalWindowDelegate()
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
    func configure() {
        guard let window else { return }
        window.level = alwaysOnTop ? .floating : .normal
        ProportionalWindowDelegate.alignWindowButtons(window)
        if window.delegate !== resizeDelegate {
            resizeDelegate.upstream = window.delegate
            window.delegate = resizeDelegate
        }
        resizeDelegate.videoSize = videoSize ?? CGSize(width: 362, height: 758)
        if !configured {
            configured = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
            window.tabbingMode = .disallowed
            if UserDefaults.standard.integer(forKey: "windowLayoutVersion") < 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak window] in
                    window?.setContentSize(NSSize(width: 374, height: 800))
                    if let window { self.resizeDelegate.constrain(window) }
                    window?.center()
                    UserDefaults.standard.set(4, forKey: "windowLayoutVersion")
                }
            }
        }
        // Full-size content includes our 12-point side inset and 42-point toolbar/footer.
        // NSWindow.contentAspectRatio alone would scale those fixed insets and leave black bars.
        // SwiftUI restoration and programmatic sizing bypass windowWillResize.
        resizeDelegate.constrain(window)
        guard previousVideoSize != videoSize else { return }
        let previous = previousVideoSize
        previousVideoSize = videoSize
        if let videoSize {
            let aspect = videoSize.width / max(1, videoSize.height)
            let visible = window.screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
            let height: CGFloat
            let width: CGFloat
            if aspect > 1 {
                width = min(820, visible.width - 80)
                height = (width - 12) / aspect + 42
            } else {
                height = min(800, visible.height - 70)
                width = max(320, (height - 42) * aspect + 12)
            }
            let fitted = MirrorWindowGeometry.fit(CGSize(width: width, height: height), video: videoSize,
                                                  limit: CGSize(width: visible.width - 30, height: visible.height - 30))
            window.setContentSize(fitted)
        } else if previous != nil {
            window.setContentSize(NSSize(width: 374, height: 800))
        }
        resizeDelegate.constrain(window)
    }
}

struct WindowDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> DragStripView { DragStripView() }
    func updateNSView(_ view: DragStripView, context: Context) {}
}

final class DragStripView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

/// Geometry is based on the video rectangle, rather than the enclosing window rectangle.
enum MirrorWindowGeometry {
    static func fit(_ proposed: CGSize, video: CGSize, limit: CGSize, drivenByHeight: Bool = true) -> CGSize {
        let ratio = video.width / max(1, video.height)
        let maximumHeight = min(max(1, limit.height - 42), max(1, limit.width - 12) / ratio)
        let minimumHeight = min(maximumHeight, max((320 - 12) / ratio, ratio > 1 ? 198 : 528))
        let requested = drivenByHeight ? proposed.height - 42 : (proposed.width - 12) / ratio
        let height = min(maximumHeight, max(minimumHeight, requested))
        return CGSize(width: height * ratio + 12, height: height + 42)
    }
}

/// Forward other window delegate callbacks to SwiftUI's existing delegate.
final class ProportionalWindowDelegate: NSObject, NSWindowDelegate {
    weak var upstream: (any NSWindowDelegate)?
    var videoSize = CGSize(width: 362, height: 758)
    private var constraining = false
    private var resizeDrivenByHeight: Bool?
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (upstream?.responds(to: selector) ?? false)
    }
    override func forwardingTarget(for selector: Selector!) -> Any? { upstream }
    static func alignWindowButtons(_ window: NSWindow) {
        guard let content = window.contentView else { return }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind), let parent = button.superview else { continue }
            let point = NSPoint(x: 0, y: content.isFlipped ? 18 : content.bounds.height - 18)
            let center = parent.convert(point, from: content)
            button.setFrameOrigin(NSPoint(x: button.frame.minX, y: center.y - button.frame.height / 2))
        }
    }
    func windowDidResize(_ notification: Notification) {
        upstream?.windowDidResize?(notification)
        guard let window = notification.object as? NSWindow else { return }
        Self.alignWindowButtons(window)
        constrain(window)
    }
    func constrain(_ window: NSWindow) {
        guard !constraining, !window.inLiveResize, !window.styleMask.contains(.fullScreen) else { return }
        let content = window.contentRect(forFrameRect: window.frame).size
        let limit = window.screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let fitted = MirrorWindowGeometry.fit(content, video: videoSize, limit: limit)
        // Native AppKit constraint keeps resize cursors stable. The delegate accounts
        // for the fixed toolbar/insets instead of scaling them with the video.
        constraining = true
        if abs(window.contentAspectRatio.width - fitted.width) > 0.5 || abs(window.contentAspectRatio.height - fitted.height) > 0.5 {
            window.contentAspectRatio = fitted
        }
        if abs(content.width - fitted.width) > 1 || abs(content.height - fitted.height) > 1 {
            window.setContentSize(fitted)
        }
        constraining = false
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let content = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        let current = sender.contentRect(forFrameRect: sender.frame).size
        let dominantHeight = abs(content.height - current.height) > abs(content.width - current.width)
        if sender.inLiveResize, resizeDrivenByHeight == nil { resizeDrivenByHeight = dominantHeight }
        let heightDriven = resizeDrivenByHeight ?? dominantHeight
        let visible = sender.screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let size = MirrorWindowGeometry.fit(content, video: videoSize, limit: visible, drivenByHeight: heightDriven)
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        resizeDrivenByHeight = nil
        upstream?.windowDidEndLiveResize?(notification)
        if let window = notification.object as? NSWindow { constrain(window); Self.alignWindowButtons(window) }
    }
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
        let content = window.contentRect(forFrameRect: defaultFrame).size
        let size = MirrorWindowGeometry.fit(content, video: videoSize, limit: content)
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        return NSRect(x: defaultFrame.midX - frame.width / 2, y: defaultFrame.maxY - frame.height,
                      width: frame.width, height: frame.height)
    }
}
