import Foundation

/// Narrow injectable device boundary; view and persistence code do not own subprocesses.
protocol ADBTransport: Sendable {
    func run(_ arguments: [String], timeout: TimeInterval) async throws -> String
    func devices() async throws -> [Device]
    func services() async throws -> [WirelessService]
    func connect(_ endpoint: String) async throws
}

extension ADBTransport {
    func run(_ arguments: [String]) async throws -> String { try await run(arguments, timeout: 15) }
}
