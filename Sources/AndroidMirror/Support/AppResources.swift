import Foundation

enum AppResources {
    static var bundle: Bundle {
        if let root = Bundle.main.resourceURL?.appendingPathComponent("AndroidMirror_AndroidMirror.bundle"),
           let bundle = Bundle(url: root) { return bundle }
        return Bundle.module
    }
    /// SwiftPM's generated accessor looks beside the .app, but our shipped resources are inside it.
    static func url(for name: String, extension suffix: String? = nil) -> URL? {
        bundle.url(forResource: name, withExtension: suffix)
    }
}
