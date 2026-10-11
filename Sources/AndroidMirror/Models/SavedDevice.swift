import Foundation

struct SavedDevice: Codable, Identifiable, Equatable {
    let id: String // ro.serialno when available; transport addresses can change.
    var name: String
    var customName: String?
    var transportID: String
    var serviceName: String?
    var endpoint: String?

    func matches(_ service: WirelessService) -> Bool {
        guard service.kind.contains("connect") else { return false }
        return service.name == serviceName || service.name.hasPrefix("adb-\(id)-")
    }
}
