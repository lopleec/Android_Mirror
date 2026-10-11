import Foundation
import Darwin

/// ADB endpoints use host:port for DNS/IPv4 and [host]:port for IPv6.
enum Endpoint {
    static func valid(_ value: String) -> Bool { parse(value) != nil }
    static func host(_ value: String) -> String { parse(value)?.host ?? value }
    static func port(_ value: String) -> String? { parse(value)?.port }
    static func normalizedHost(_ host: String) -> String {
        host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }
    static func address(host: String, port: String) -> String {
        let raw = normalizedHost(host)
        return raw.contains(":") ? "[\(raw)]:\(port)" : "\(raw):\(port)"
    }
    private static func parse(_ value: String) -> (host: String, port: String)? {
        let host: String, port: String
        if value.hasPrefix("[") {
            guard let closing = value.firstIndex(of: "]"), value[value.index(after: closing)...].hasPrefix(":") else { return nil }
            host = String(value[value.index(after: value.startIndex)..<closing])
            port = String(value[value.index(closing, offsetBy: 2)...])
            let pieces = host.split(separator: "%", omittingEmptySubsequences: false)
            guard pieces.count <= 2, let literal = pieces.first, !literal.isEmpty else { return nil }
            if pieces.count == 2, !safeName(String(pieces[1])) { return nil }
            var bytes = in6_addr()
            guard String(literal).withCString({ inet_pton(AF_INET6, $0, &bytes) }) == 1 else { return nil }
        } else {
            let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 2 else { return nil }
            host = String(pieces[0]); port = String(pieces[1])
            guard safeName(host) else { return nil }
        }
        guard !port.isEmpty, port.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(port), (1...65535).contains(number) else { return nil }
        return (host, port)
    }
    private static func safeName(_ value: String) -> Bool {
        !value.isEmpty && value.first != "-" && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46 || $0 == 95
        }
    }
}
