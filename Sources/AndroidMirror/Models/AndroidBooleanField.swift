import Foundation

/// dumpsys fields differ between Android releases. Missing or conflicting fields stay unknown.
struct AndroidBooleanField {
    enum Reading: Equatable { case absent, value(Bool), conflicting }
    private let expression: NSRegularExpression
    init(_ pattern: String) {
        expression = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
    func read(_ output: String) -> Reading {
        let matches = expression.matches(in: output, range: NSRange(output.startIndex..., in: output))
        guard !matches.isEmpty else { return .absent }
        let values = Set(matches.compactMap { Range($0.range(at: 1), in: output).map { output[$0].lowercased() == "true" } })
        guard values.count == 1, let value = values.first else { return .conflicting }
        return .value(value)
    }
}
