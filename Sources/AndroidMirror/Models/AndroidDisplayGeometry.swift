import Foundation

/// Use primary-display input coordinates when available, with wm/video as a legacy fallback.
enum AndroidDisplayGeometry {
    private static let viewports = try! NSRegularExpression(pattern: #"DisplayViewport\{([^}]+)\}"#)
    private static let frames = [
        try! NSRegularExpression(pattern: #"logicalFrame=\[\s*(-?\d+),\s*(-?\d+),\s*(-?\d+),\s*(-?\d+)\]"#),
        try! NSRegularExpression(pattern: #"logicalFrame=Rect\(\s*(-?\d+),\s*(-?\d+)\s*-\s*(-?\d+),\s*(-?\d+)\)"#)
    ]
    private static let dimensions = try! NSRegularExpression(pattern: #"(?:Physical|Override) size:\s*(\d+)x(\d+)"#)

    static func primaryViewport(_ output: String) -> CGSize? {
        for match in viewports.matches(in: output, range: NSRange(output.startIndex..., in: output)) {
            guard let range = Range(match.range(at: 1), in: output) else { continue }
            let viewport = String(output[range])
            guard viewport.range(of: #"\bdisplayId=0\b"#, options: .regularExpression) != nil,
                  !viewport.contains("valid=false"), !viewport.contains("isActive=false"),
                  let logical = frames.compactMap({ $0.firstMatch(in: viewport, range: NSRange(viewport.startIndex..., in: viewport)) }).first else { continue }
            let values = (1...4).compactMap { index -> Double? in
                Range(logical.range(at: index), in: viewport).flatMap { Double(viewport[$0]) }
            }
            guard values.count == 4, values[0] == 0, values[1] == 0, values[2] > 0, values[3] > 0 else { continue }
            return CGSize(width: values[2], height: values[3])
        }
        return nil
    }
    static func screenSize(_ output: String, orientation: CGSize) throws -> CGSize {
        guard let match = dimensions.matches(in: output, range: NSRange(output.startIndex..., in: output)).last,
              let w = Range(match.range(at: 1), in: output), let h = Range(match.range(at: 2), in: output),
              let width = Double(output[w]), let height = Double(output[h]), width > 0, height > 0 else {
            throw MirrorError.message(L10n.tr("Could not read the phone screen size. No password was sent."))
        }
        return (width > height) == (orientation.width > orientation.height) ? CGSize(width: width, height: height) : CGSize(width: height, height: width)
    }
}
