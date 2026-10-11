import XCTest
import Darwin
@testable import AndroidMirror

final class SocketTests: XCTestCase {
    private func listener() throws -> (Int32, UInt16) {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MirrorError.message("socket") }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0, Darwin.listen(fd, 1) == 0 else { Darwin.close(fd); throw MirrorError.message("bind") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        return (fd, UInt16(bigEndian: address.sin_port))
    }
    func testPartialSocketReadsAndWritesPreservePacket() throws {
        let (listener, port) = try listener()
        defer { Darwin.close(listener) }
        let serverDone = expectation(description: "Server received intact clipboard packet")
        let packet = ControlPacket.clipboard("你好 Android", paste: true)
        DispatchQueue.global().async {
            let peer = accept(listener, nil, nil)
            guard peer >= 0 else { XCTFail("accept failed"); serverDone.fulfill(); return }
            defer { Darwin.close(peer) }
            for byte: UInt8 in [1, 2, 3, 4] {
                var value = byte
                _ = Darwin.send(peer, &value, 1, 0)
            }
            var received = Data(count: packet.count)
            received.withUnsafeMutableBytes { raw in
                var offset = 0
                while offset < packet.count {
                    let size = recv(peer, raw.baseAddress!.advanced(by: offset), packet.count - offset, 0)
                    guard size > 0 else { break }
                    offset += size
                }
            }
            XCTAssertEqual(received, packet); serverDone.fulfill()
        }
        let socket = try LocalSocket(port: port)
        socket.timeout(2)
        XCTAssertEqual(try socket.read(4), Data([1, 2, 3, 4]))
        try socket.write(packet)
        wait(for: [serverDone], timeout: 3)
    }
    func testShutdownInterruptsBlockedReader() throws {
        let (listener, port) = try listener()
        defer { Darwin.close(listener) }
        let socket = try LocalSocket(port: port)
        let peer = accept(listener, nil, nil)
        defer { Darwin.close(peer) }
        let interrupted = expectation(description: "Reader unblocked on cancel")
        DispatchQueue.global().async {
            do { _ = try socket.read(12); XCTFail("Read must fail after shutdown") } catch {}
            interrupted.fulfill()
        }
        socket.shutdown()
        wait(for: [interrupted], timeout: 2)
        XCTAssertThrowsError(try socket.read(16 * 1024 * 1024 + 1))
    }
}
