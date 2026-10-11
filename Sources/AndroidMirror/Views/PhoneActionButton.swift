import SwiftUI

struct PhoneActionButton: View {
    let action: PhoneAction
    let store: MirrorStore
    var includeShortcut = false
    var body: some View {
        if includeShortcut, let shortcut = action.shortcut {
            button.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else { button }
    }
    private var button: some View {
        Button(action.title(screenOff: store.screenOff)) { store.perform(action) }
            .disabled(!store.isEnabled(action))
    }
}
