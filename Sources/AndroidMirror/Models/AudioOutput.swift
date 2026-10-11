import Foundation

enum AudioOutput: String, CaseIterable, Identifiable {
    case phone, computer
    var id: String { rawValue }
    var title: String { self == .phone ? L10n.tr("Phone Speaker") : L10n.tr("Mac Speaker") }
}
