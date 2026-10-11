import Foundation
import Observation

/// Discovers transports, groups them by physical phone and persists only known devices.
@MainActor @Observable
final class DeviceRegistry {
    private(set) var devices: [Device] = []
    private(set) var saved: [SavedDevice]
    private(set) var refreshing = false
    private(set) var usbDevices: [Device] = []
    @ObservationIgnored private let adb: any ADBTransport
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lastAttempt: [String: Date] = [:]
    @ObservationIgnored private var forgotten: Set<String>
    @ObservationIgnored private var identities: [String: String] = [:]

    init(adb: any ADBTransport = ADBClient(), defaults: UserDefaults = .standard) {
        self.adb = adb; self.defaults = defaults
        forgotten = Set(defaults.stringArray(forKey: "forgottenDevices") ?? [])
        saved = defaults.data(forKey: "savedDevices").flatMap { try? JSONDecoder().decode([SavedDevice].self, from: $0) } ?? []
    }
    func refresh(autoReconnect: Bool, activeTransportID: String? = nil) async throws {
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        try await loadDevices(activeTransportID: activeTransportID)
        guard autoReconnect, !saved.isEmpty else { return }
        let services = (try? await adb.services()) ?? []
        for record in saved where !isOnline(record) {
            guard let service = services.first(where: record.matches),
                  Date().timeIntervalSince(lastAttempt[service.endpoint] ?? .distantPast) > 12 else { continue }
            lastAttempt[service.endpoint] = Date()
            // Never pair arbitrary broadcasts or reconnect to an unrelated phone.
            if (try? await adb.connect(service.endpoint)) != nil { try await loadDevices(activeTransportID: activeTransportID) }
        }
    }
    func device(for transportID: String) -> Device? {
        devices.first { $0.id == transportID || identities[$0.id] == transportID || identities[$0.id] == identities[transportID] && identities[transportID] != nil }
    }
    func credentialAccount(for device: Device) -> String? {
        guard let identity = identities[device.id], !identity.isEmpty else { return nil }
        // A recycled wireless address must never be the key to a phone password.
        return identity == device.id && device.wireless ? nil : identity
    }
    func record(for device: Device) -> SavedDevice? {
        saved.first { $0.id == identities[device.id] || $0.transportID == device.id }
    }
    func displayName(for device: Device) -> String { record(for: device)?.name ?? device.name }
    func rename(_ record: SavedDevice, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = saved.firstIndex(where: { $0.id == record.id }) else { return }
        saved[index].name = String(name.prefix(64)); saved[index].customName = saved[index].name
        persist()
    }
    func allowDevice(_ transportID: String) async throws {
        let transports = try await adb.devices()
        if let device = transports.first(where: { $0.id == transportID }) {
            forgotten.remove(await readIdentity(device)); persist()
        }
        try await loadDevices()
    }
    func isOnline(_ record: SavedDevice) -> Bool {
        devices.contains { $0.ready && ($0.id == record.transportID || identities[$0.id] == record.id) }
    }
    func remember(_ device: Device) async {
        let identity: String
        if let known = identities[device.id] { identity = known } else { identity = await readIdentity(device) }
        let services = device.wireless ? (try? await adb.services()) ?? [] : []
        let service = services.first { $0.kind.contains("connect") &&
            ($0.name.hasPrefix("adb-\(identity)-") || device.id.hasPrefix($0.name) || $0.endpoint == device.id) }
        guard !forgotten.contains(identity) else { return }
        let previous = saved.first { $0.id == identity }
        let record = SavedDevice(id: identity, name: previous?.customName ?? device.name, customName: previous?.customName, transportID: device.id,
            serviceName: service?.name ?? previous?.serviceName,
            endpoint: service?.endpoint ?? (Endpoint.valid(device.id) ? device.id : previous?.endpoint))
        if let index = saved.firstIndex(where: { $0.id == identity }) { saved[index] = record } else { saved.append(record) }
        persist()
    }
    func reconnect(_ record: SavedDevice) async throws -> Device {
        try await loadDevices()
        if let device = devices.first(where: { $0.ready && ($0.id == record.transportID || identities[$0.id] == record.id) }) {
            return device
        }
        let services = (try? await adb.services()) ?? []
        let discovered = services.first(where: record.matches)
        guard let endpoint = discovered?.endpoint ?? record.endpoint else {
            throw MirrorError.message(L10n.tr("Phone not found. Connect USB or enable Wireless debugging on your phone."))
        }
        try await adb.connect(endpoint)
        try await loadDevices()
        guard let device = devices.first(where: { device in
            device.ready && (identities[device.id] == record.id || device.id == endpoint ||
                             (discovered.map { device.id.hasPrefix($0.name) } ?? false))
        }) else { throw MirrorError.message(L10n.tr("This phone is not connected. Check its Wireless debugging connection port.")) }
        if let identity = identities[device.id], identity != device.id,
           record.id != record.transportID, identity != record.id {
            throw MirrorError.message(L10n.tr("This address now belongs to another phone. Rediscover your saved device."))
        }
        return device
    }
    func forget(_ record: SavedDevice) {
        saved.removeAll { $0.id == record.id }; forgotten.insert(record.id)
        devices.removeAll { $0.id == record.transportID || identities[$0.id] == record.id }
        persist()
    }

    private func readIdentity(_ device: Device) async -> String {
        guard device.ready else { return device.id }
        let serial = ((try? await adb.run(["-s", device.id, "shell", "getprop", "ro.serialno"], timeout: 3)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return serial.isEmpty || ["unknown", "null"].contains(serial.lowercased()) ? device.id : serial
    }
    private func loadDevices(activeTransportID: String? = nil) async throws {
        let transports = try await adb.devices()
        usbDevices = transports.filter { $0.ready && !$0.wireless }
        var refreshed: [String: String] = [:]
        for device in transports { refreshed[device.id] = await readIdentity(device) }
        // Use authorized USB when idle, but never change an active session's transport.
        // An unauthorized/offline USB endpoint must not hide a working wireless endpoint.
        let preferredIDs = Set(devices.map(\.id))
        let stable = transports.filter { preferredIDs.contains($0.id) } + transports.filter { !preferredIDs.contains($0.id) }
        func priority(_ device: Device) -> Int {
            guard device.ready else { return 3 }
            if device.id == activeTransportID { return 0 }
            return device.wireless ? 2 : 1
        }
        let ordered = stable.enumerated().sorted {
            let first = priority($0.element), second = priority($1.element)
            return first == second ? $0.offset < $1.offset : first < second
        }.map(\.element)
        var seen: Set<String> = []
        devices = ordered.filter { device in
            let identity = refreshed[device.id] ?? device.id
            let visible = !forgotten.contains(identity) || (device.ready && !device.wireless)
            return visible && seen.insert(identity).inserted
        }
        identities = refreshed
    }
    private func persist() {
        defaults.set(try? JSONEncoder().encode(saved), forKey: "savedDevices")
        defaults.set(Array(forgotten), forKey: "forgottenDevices")
    }
}
