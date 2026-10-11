import Foundation
import Darwin

/// Shutdown interrupts readers; the descriptor is only closed on deinit to avoid fd reuse races.
final class LocalSocket: @unchecked Sendable {
    private let fd: Int32
    init(port: UInt16) throws {
        fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MirrorError.message(L10n.tr("Could not create a mirroring connection.")) }
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { Darwin.close(fd); throw MirrorError.message(L10n.tr("The phone mirroring service is not ready.")) }
    }
    deinit { Darwin.close(fd) }
    func shutdown() { Darwin.shutdown(fd, SHUT_RDWR) }
    func timeout(_ seconds: Int) {
        var value = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }
    func readTimeout(_ seconds: Int) {
        var value = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }
    func read(_ count: Int) throws -> Data {
        guard count >= 0 && count <= 16 * 1024 * 1024 else { throw MirrorError.message(L10n.tr("Invalid mirroring data length.")) }
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { raw in
            var offset = 0
            while offset < count {
                let length = recv(fd, raw.baseAddress!.advanced(by: offset), count - offset, 0)
                if length < 0 && errno == EINTR { continue }
                guard length > 0 else { throw MirrorError.message(L10n.tr("The phone connection was interrupted. Check Wireless debugging or USB.")) }
                offset += length
            }
        }
        return data
    }
    func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < data.count {
                let length = send(fd, raw.baseAddress!.advanced(by: offset), data.count - offset, 0)
                if length < 0 && errno == EINTR { continue }
                guard length > 0 else { throw MirrorError.message(L10n.tr("Could not send input to the phone.")) }
                offset += length
            }
        }
    }
}
