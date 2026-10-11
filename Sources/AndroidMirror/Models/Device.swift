import Foundation

struct Device: Identifiable, Equatable {
    let id: String
    let name: String
    let state: String
    var wireless: Bool { id.contains(":") || id.contains("_adb-tls") }
    var ready: Bool { state == "device" }
    var status: String {
        switch state {
        case "device": return wireless ? L10n.tr("Wireless") : L10n.tr("USB")
        case "unauthorized": return L10n.tr("Allow USB debugging on your phone")
        default: return L10n.tr("Offline")
        }
    }

    static func parse(_ output: String) -> [Device] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2, ["device", "offline", "unauthorized"].contains(parts[1]) else { return nil }
            let model = parts.first(where: { $0.hasPrefix("model:") })?.dropFirst(6)
            return Device(id: parts[0], name: model.map { String($0).replacingOccurrences(of: "_", with: " ") } ?? "Android", state: parts[1])
        }
    }
}

struct WirelessService: Equatable {
    let name: String
    let kind: String
    let endpoint: String
    static func parse(_ output: String) -> [WirelessService] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 3, parts[1].contains("_adb-tls-") else { return nil }
            return WirelessService(name: parts[0], kind: parts[1], endpoint: parts[2])
        }
    }
}
