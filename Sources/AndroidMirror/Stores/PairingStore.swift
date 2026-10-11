import Foundation
import Observation
import CoreImage.CIFilterBuiltins
import AppKit

@MainActor @Observable
final class PairingStore {
    var host = ""
    var pairPort = ""
    var code = ""
    var connectPort = ""
    var busy = false
    var message = ""
    var error: String?
    var qrImage: NSImage?
    var qrExpired = false
    var paired = false
    var connectedID: String?
    private var qrTask: Task<Void, Never>?
    private let adb = ADBClient()
    private var qrGeneration = UUID()

    var canPair: Bool { Endpoint.valid(Endpoint.address(host: host, port: pairPort)) && code.utf8.count == 6 && code.utf8.allSatisfy { (48...57).contains($0) } && !busy }
    var canConnect: Bool { Endpoint.valid(Endpoint.address(host: host, port: connectPort)) && !busy }

    func startQR() {
        cancelQR(); error = nil; paired = false; qrExpired = false
        let generation = UUID(); qrGeneration = generation
        let name = "studio-lopleec-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let password = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let payload = "WIFI:T:ADB;S:\(name);P:\(password);;"
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8); filter.correctionLevel = "M"
        if let image = filter.outputImage,
           let cg = CIContext().createCGImage(image.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: image.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) {
            qrImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        message = L10n.tr("Waiting for scan…")
        qrTask = Task {
            let expires = Date().addingTimeInterval(120)
            while !Task.isCancelled && Date() < expires {
                do {
                    let services = try await adb.services()
                    guard !Task.isCancelled, qrGeneration == generation else { return }
                    if let service = services.first(where: { $0.kind.contains("pairing") && ($0.name == name || $0.name.hasPrefix(name + ".")) }) {
                        busy = true; message = L10n.tr("Pairing securely…")
                        try await adb.pair(endpoint: service.endpoint, code: password)
                        guard !Task.isCancelled, qrGeneration == generation else { busy = false; return }
                        paired = true; host = Endpoint.host(service.endpoint)
                        try await finishPairing(host: Endpoint.normalizedHost(host))
                        busy = false; return
                    }
                } catch {
                    guard !Task.isCancelled, qrGeneration == generation else { return }
                    self.error = error.localizedDescription.replacingOccurrences(of: password, with: "••••••")
                    busy = false; return
                }
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, qrGeneration == generation else { return }
            qrExpired = true; qrImage = nil; message = L10n.tr("The QR code has expired. Refresh it to continue.")
        }
    }
    func cancelQR() { qrGeneration = UUID(); qrTask?.cancel(); qrTask = nil; qrImage = nil }

    func pairWithCode() async {
        guard canPair else { return }
        busy = true; error = nil; message = L10n.tr("Pairing securely…")
        defer { busy = false }
        do {
            try await adb.pair(endpoint: Endpoint.address(host: host, port: pairPort), code: code)
            code = ""; paired = true
            try await finishPairing(host: Endpoint.normalizedHost(host))
        } catch { self.error = error.localizedDescription; message = "" }
    }
    func connectManually() async {
        guard canConnect else { return }
        busy = true; error = nil; message = L10n.tr("Connecting to phone…")
        defer { busy = false }
        do {
            let endpoint = Endpoint.address(host: host, port: connectPort)
            try await adb.connect(endpoint)
            let devices = try await adb.devices()
            guard let device = devices.first(where: { $0.ready && ($0.id == endpoint || Endpoint.host($0.id) == Endpoint.host(endpoint)) }) else {
                throw MirrorError.message(L10n.tr("The device is not ready. Allow debugging on your phone and try again."))
            }
            connectedID = device.id; message = L10n.tr("Connected")
        } catch { self.error = error.localizedDescription; message = "" }
    }
    private func finishPairing(host: String) async throws {
        message = L10n.tr("Paired. Finding the connection port…")
        for _ in 0..<12 {
            guard !Task.isCancelled else { return }
            let devices = try await adb.devices()
            if let device = devices.first(where: { $0.ready && Endpoint.host($0.id) == host }) {
                connectedID = device.id; message = L10n.tr("Connected"); return
            }
            let services = try await adb.services()
            if let service = services.first(where: { $0.kind.contains("connect") && Endpoint.host($0.endpoint) == host }) {
                connectPort = Endpoint.port(service.endpoint) ?? ""
                try await adb.connect(service.endpoint)
                let refreshed = try await adb.devices()
                if let device = refreshed.first(where: { $0.ready && ($0.id == service.endpoint || $0.id.hasPrefix(service.name) || Endpoint.host($0.id) == host) }) {
                    connectedID = device.id; message = L10n.tr("Connected"); return
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
        message = L10n.tr("Paired. Enter the connection port from the main Wireless debugging page.")
    }
}
