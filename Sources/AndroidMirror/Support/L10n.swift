import Foundation

/// One localization boundary for SwiftUI, AppKit, errors and background services.
/// The resource bundle resolves the system's preferred app language, falling back to English.
enum L10n {
    static func tr(_ key: String, language: String? = nil) -> String {
        let resources = AppResources.bundle
        let selected: Bundle
        if let language {
            // SwiftPM normalizes lproj names to lowercase. Resolve by the bundle's
            // declared localizations, rather than relying on resource-name casing.
            let name = resources.localizations.first { $0.caseInsensitiveCompare(language) == .orderedSame } ?? "en"
            if let root = resources.resourceURL,
               let bundle = Bundle(url: root.appendingPathComponent(name + ".lproj")) { selected = bundle }
            else { selected = resources }
        } else { selected = resources }
        return selected.localizedString(forKey: key, value: key, table: nil)
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: arguments)
    }
    static func minutes(_ count: Int) -> String {
        count == 1 ? tr("1 minute") : format("%ld minutes", count)
    }
    static var guideURL: URL? {
        let language = AppResources.bundle.preferredLocalizations.first ?? "en"
        return AppResources.url(for: language.hasPrefix("zh") ? "Guide-zh-Hans" : "Guide-en", extension: "html")
    }
}
