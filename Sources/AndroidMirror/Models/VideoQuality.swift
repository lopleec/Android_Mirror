import Foundation

/// Encoder bandwidth is independent of capture resolution and display color space.
enum VideoQuality: String, CaseIterable, Identifiable {
    case standard, high, maximum
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return L10n.tr("Standard")
        case .high: return L10n.tr("High Quality")
        case .maximum: return L10n.tr("Maximum Quality")
        }
    }
    func bitRate(maxSize: Int) -> Int {
        switch (self, maxSize) {
        case (.standard, 1280): return 4_000_000
        case (.standard, 0): return 12_000_000
        case (.standard, _): return 8_000_000
        case (.high, 1280): return 8_000_000
        case (.high, 0): return 24_000_000
        case (.high, _): return 16_000_000
        case (.maximum, 1280): return 12_000_000
        case (.maximum, 0): return 32_000_000
        case (.maximum, _): return 24_000_000
        }
    }
}
