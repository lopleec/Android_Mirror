import XCTest
@testable import AndroidMirror

final class ProtocolTests: XCTestCase {
    func testADBDeviceStatesAndModels() {
        let result = Device.parse("List of devices attached\n192.168.1.8:45555 device product:foo model:Pixel_9a\nabc unauthorized usb:1\nxyz offline\n")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].name, "Pixel 9a")
        XCTAssertTrue(result[0].wireless)
        XCTAssertFalse(result[1].ready)
    }
    func testMDNSPairAndConnectAreDistinct() {
        let services = WirelessService.parse("List of discovered mdns services\nstudio-foo _adb-tls-pairing._tcp. 192.168.1.8:33445\nadb-serial _adb-tls-connect._tcp. 192.168.1.8:45678")
        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services[0].endpoint, "192.168.1.8:33445")
        XCTAssertTrue(services[1].kind.contains("connect"))
    }
    func testEndpointRejectsMalformedAndShellInput() {
        XCTAssertTrue(Endpoint.valid("192.168.1.8:33445"))
        for value in ["", "192.168.1.8:0", "192.168.1.8:65536", "-s:5000", "a;rm:1234", "192.168.1.8", "x:12:34"] {
            XCTAssertFalse(Endpoint.valid(value), value)
        }
    }
    func testTouchCoordinatesMatchScrcpyWireFormat() {
        let packet = ControlPacket.touch(action: 0, x: 123, y: 456, width: 1080, height: 2400)
        XCTAssertEqual(packet.count, 32)
        XCTAssertEqual(packet.prefix(2), Data([2, 0]))
        XCTAssertEqual(packet.integer(at: 2, as: UInt64.self), UInt64.max - 1)
        XCTAssertEqual(packet.integer(at: 10, as: UInt32.self), 123)
        XCTAssertEqual(packet.integer(at: 18, as: UInt16.self), 1080)
        XCTAssertEqual(packet.integer(at: 22, as: UInt16.self), 65535)
        XCTAssertEqual(ControlPacket.touch(action: 1, x: 0, y: 0, width: 1, height: 1).integer(at: 22, as: UInt16.self), 0)
    }
    func testUnicodeClipboardAndTruncationRemainValidUTF8() {
        let text = "你好 👋 Hello"
        let packet = ControlPacket.clipboard(text, paste: true, sequence: 42)
        XCTAssertEqual(packet[0], 9)
        XCTAssertEqual(packet.integer(at: 1, as: UInt64.self), 42)
        XCTAssertEqual(packet[9], 1)
        XCTAssertEqual(packet.integer(at: 10, as: UInt32.self), UInt32(text.utf8.count))
        XCTAssertEqual(String(data: packet.dropFirst(14), encoding: .utf8), text)
        XCTAssertEqual(String(data: ControlPacket.utf8("你好吗", limit: 7), encoding: .utf8), "你好")
    }
    func testAnnexBHandlesThreeAndFourByteDelimiters() {
        let stream = Data([0, 0, 0, 1, 0x67, 0x42, 0, 0, 1, 0x68, 0xab, 0, 0, 0, 1, 0x65, 0x88])
        XCTAssertEqual(H264Decoder.units(stream), [Data([0x67, 0x42]), Data([0x68, 0xab]), Data([0x65, 0x88])])
        XCTAssertTrue(H264Decoder.units(Data()).isEmpty)
    }
    func testScrollAndKeyPackets() {
        let key = ControlPacket.key(66, down: true, modifiers: 0x1000)
        XCTAssertEqual(key.count, 14)
        XCTAssertEqual(key.integer(at: 2, as: UInt32.self), 66)
        XCTAssertEqual(key.integer(at: 10, as: UInt32.self), 0x1000)
        let scroll = ControlPacket.scroll(x: 0, y: 0, width: 1080, height: 2400, dx: -16, dy: 16)
        XCTAssertEqual(scroll.count, 21)
        XCTAssertEqual(scroll.integer(at: 13, as: UInt16.self), 0x8000)
        XCTAssertEqual(scroll.integer(at: 15, as: UInt16.self), 0x7fff)
    }
}
