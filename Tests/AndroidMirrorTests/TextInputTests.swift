import XCTest
@testable import AndroidMirror

final class TextInputTests: XCTestCase {
    func testDirectTextPacketsPreserveUnicodeSelectionsAndNeverUseClipboardControl() throws {
        for text in ["中文输入🙂", "你好\n第二行", "abc"] {
            let packet = try UnicodeInputSession.packet(text)
            XCTAssertEqual(packet.integer(at: 0, as: UInt32.self), UInt32(text.utf8.count))
            XCTAssertEqual(String(decoding: packet.dropFirst(4), as: UTF8.self), text)
        }
        XCTAssertThrowsError(try UnicodeInputSession.packet(""))
        XCTAssertThrowsError(try UnicodeInputSession.packet(String(repeating: "中", count: 30000)))
    }
}
