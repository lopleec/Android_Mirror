import SwiftUI
import AppKit
import AVFoundation

struct MirrorSurface: NSViewRepresentable {
    let store: MirrorStore
    func makeNSView(context: Context) -> PhoneInputView {
        let view = PhoneInputView(store: store)
        return view
    }
    func updateNSView(_ view: PhoneInputView, context: Context) {
        if view.frameSize != store.size { view.frameSize = store.size; view.needsLayout = true }
        if !store.acceptsPhoneInput {
            view.cancelInput()
            if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
        }
    }
    static func dismantleNSView(_ view: PhoneInputView, coordinator: ()) { view.store.displayLayer.removeFromSuperlayer() }
}

/// AppKit is confined to the video layer and responder/input-method boundary.
final class PhoneInputView: NSView, NSTextInputClient {
    let store: MirrorStore
    var frameSize: CGSize
    private var composing = NSMutableAttributedString()
    private var dragging = false
    override var acceptsFirstResponder: Bool { store.acceptsPhoneInput }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { true }
    init(store: MirrorStore) {
        self.store = store; frameSize = store.size
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(store.displayLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        store.displayLayer.frame = bounds
        CATransaction.commit()
    }
    private func point(_ event: NSEvent) -> (Int, Int)? {
        let location = convert(event.locationInWindow, from: nil)
        let scale = min(bounds.width / frameSize.width, bounds.height / frameSize.height)
        guard scale > 0 else { return nil }
        let origin = CGPoint(x: (bounds.width - frameSize.width * scale) / 2, y: (bounds.height - frameSize.height * scale) / 2)
        let x = (location.x - origin.x) / scale, y = (location.y - origin.y) / scale
        guard dragging || (x >= 0 && y >= 0 && x < frameSize.width && y < frameSize.height) else { return nil }
        return (Int(max(0, min(frameSize.width - 1, x))), Int(max(0, min(frameSize.height - 1, y))))
    }
    private func touch(_ event: NSEvent, action: UInt8) {
        guard let (x, y) = point(event) else { return }
        store.input(ControlPacket.touch(action: action, x: x, y: y, width: Int(frameSize.width), height: Int(frameSize.height)))
    }
    override func mouseDown(with event: NSEvent) {
        guard store.acceptsPhoneInput else { return }
        window?.makeFirstResponder(self)
        guard point(event) != nil else { return }
        dragging = true; touch(event, action: 0)
    }
    override func mouseDragged(with event: NSEvent) { if dragging { touch(event, action: 2) } }
    override func mouseUp(with event: NSEvent) { if dragging { touch(event, action: 1) }; dragging = false }
    override func rightMouseDown(with event: NSEvent) { store.key(4) }
    override func scrollWheel(with event: NSEvent) {
        guard let (x, y) = point(event) else { return }
        let factor = event.hasPreciseScrollingDeltas ? 0.035 : 0.7
        store.input(ControlPacket.scroll(x: x, y: y, width: Int(frameSize.width), height: Int(frameSize.height), dx: event.scrollingDeltaX * factor, dy: event.scrollingDeltaY * factor))
    }
    override func keyDown(with event: NSEvent) { if store.acceptsPhoneInput { interpretKeyEvents([event]) } }
    @objc func copy(_ sender: Any?) { store.copy() }
    @objc func cut(_ sender: Any?) { store.copy(cut: true) }
    @objc func paste(_ sender: Any?) { store.paste() }
    override func selectAll(_ sender: Any?) { store.key(29, modifiers: 0x1000) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard store.acceptsPhoneInput, window?.firstResponder === self, event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": store.copy()
        case "x": store.copy(cut: true)
        case "v": store.paste()
        case "a": store.key(29, modifiers: 0x1000)
        case "z": store.key(54, modifiers: event.modifierFlags.contains(.shift) ? 0x1001 : 0x1000)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
    override func resignFirstResponder() -> Bool {
        cancelInput()
        return super.resignFirstResponder()
    }
    func cancelInput() {
        if dragging {
            // Cancel only the in-flight pointer, without completing a tap underneath
            // the new lock overlay. Ordinary input remains blocked by the store.
            store.session?.send(ControlPacket.touch(action: 3, x: 0, y: 0, width: Int(frameSize.width), height: Int(frameSize.height)))
            dragging = false
        }
        unmarkText()
    }
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard store.acceptsPhoneInput else { return }
        let text = (string as? NSAttributedString)?.string ?? (string as? String ?? "")
        unmarkText()
        guard !text.isEmpty else { return }
        store.typeText(text)
    }
    override func doCommand(by selector: Selector) {
        let code: UInt32?
        switch NSStringFromSelector(selector) {
        case "deleteBackward:": code = 67
        case "deleteForward:": code = 112
        case "insertNewline:", "insertLineBreak:": code = 66
        case "insertTab:": code = 61
        case "insertBacktab:": store.key(61, modifiers: 1); return
        case "moveLeft:", "moveLeftAndModifySelection:": code = 21
        case "moveRight:", "moveRightAndModifySelection:": code = 22
        case "moveUp:", "moveUpAndModifySelection:": code = 19
        case "moveDown:", "moveDownAndModifySelection:": code = 20
        case "moveToBeginningOfLine:": code = 122
        case "moveToEndOfLine:": code = 123
        case "moveWordLeft:": store.key(21, modifiers: 0x1000); return
        case "moveWordRight:": store.key(22, modifiers: 0x1000); return
        case "deleteWordBackward:": store.key(67, modifiers: 0x1000); return
        case "pageUp:": code = 92
        case "pageDown:": code = 93
        case "cancelOperation:": code = 4
        default: code = nil
        }
        if let code { store.key(code, modifiers: NSStringFromSelector(selector).contains("ModifySelection") ? 1 : 0) }
    }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        composing = (string as? NSAttributedString).map { NSMutableAttributedString(attributedString: $0) }
            ?? NSMutableAttributedString(string: string as? String ?? "")
    }
    func unmarkText() { composing = NSMutableAttributedString() }
    func hasMarkedText() -> Bool { composing.length > 0 }
    func markedRange() -> NSRange { hasMarkedText() ? NSRange(location: 0, length: composing.length) : NSRange(location: NSNotFound, length: 0) }
    func selectedRange() -> NSRange { NSRange(location: composing.length, length: 0) }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func characterIndex(for point: NSPoint) -> Int { 0 }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(NSRect(x: 24, y: bounds.height - 70, width: 1, height: 20), to: nil))
    }
}
