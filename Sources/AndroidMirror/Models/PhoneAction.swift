import SwiftUI

/// The menu bar and window menu share labels, eligibility, routing and shortcuts.
enum PhoneAction: CaseIterable, Identifiable {
    case home, recentApps, notifications, back, screenshot, rotate, wake, screenPower, unlock, directMirror
    var id: Self { self }
    func title(screenOff: Bool) -> String {
        switch self {
        case .home: return L10n.tr("Home")
        case .recentApps: return L10n.tr("Recent Apps")
        case .notifications: return L10n.tr("Notifications")
        case .back: return L10n.tr("Back")
        case .screenshot: return L10n.tr("Save Screenshot…")
        case .rotate: return L10n.tr("Rotate Screen")
        case .wake: return L10n.tr("Wake Phone")
        case .screenPower: return L10n.tr(screenOff ? "Turn Phone Screen On" : "Turn Phone Screen Off")
        case .unlock: return L10n.tr("Enter Unlock Password…")
        case .directMirror: return L10n.tr("Direct Mirroring")
        }
    }
    var shortcut: (key: KeyEquivalent, modifiers: EventModifiers)? {
        switch self {
        case .home: return ("1", .command)
        case .recentApps: return ("2", .command)
        case .notifications: return ("3", .command)
        case .back: return ("[", .command)
        case .screenshot: return ("s", [.command, .shift])
        case .wake: return ("o", [.command, .shift])
        case .unlock: return ("u", [.command, .shift])
        case .rotate, .screenPower, .directMirror: return nil
        }
    }
}
