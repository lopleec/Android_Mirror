import AppKit
import SwiftUI

/// Weak window reference prevents authentication results from revealing a secret in a background window.
final class PrivacyWindowScope {
    weak var window: NSWindow?
}
struct PrivacyWindowAnchor: NSViewRepresentable {
    let scope: PrivacyWindowScope
    func makeNSView(context: Context) -> PrivacyAnchorView { PrivacyAnchorView(scope: scope) }
    func updateNSView(_ view: PrivacyAnchorView, context: Context) { view.scope = scope; scope.window = view.window }
}
final class PrivacyAnchorView: NSView {
    var scope: PrivacyWindowScope
    init(scope: PrivacyWindowScope) { self.scope = scope; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scope.window = window }
}
