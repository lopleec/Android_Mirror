import XCTest
@testable import AndroidMirror

final class AudioTests: XCTestCase {
    func testStereoPCMEndianSignAndChannelOrder() throws {
        let data = Data([0xff, 0x7f, 0x00, 0x80, 0x00, 0x00, 0x00, 0x40])
        let buffer = try XCTUnwrap(PhonePCM.buffer(data))
        XCTAssertEqual(buffer.frameLength, 2)
        XCTAssertEqual(buffer.format.sampleRate, 48_000)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertEqual(channels[0][0], 32767.0 / 32768, accuracy: 0.00001)
        XCTAssertEqual(channels[1][0], -1)
        XCTAssertEqual(channels[0][1], 0)
        XCTAssertEqual(channels[1][1], 0.5)
        XCTAssertNil(PhonePCM.buffer(Data([0, 1, 2])))
        XCTAssertNil(PhonePCM.buffer(Data()))
    }
    @MainActor func testAudioRoutePersistsAndPhoneOutputDisablesCapture() {
        let name = "com.lopleec.androidmirror.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = MirrorPreferences(defaults: defaults)
        XCTAssertEqual(preferences.audioOutput, .computer)
        XCTAssertTrue(preferences.configuration.serverArguments(scid: "abc").contains("audio=true"))
        XCTAssertTrue(preferences.configuration.serverArguments(scid: "abc").contains("audio_codec=raw"))
        preferences.audioOutput = .phone
        XCTAssertTrue(preferences.configuration.serverArguments(scid: "abc").contains("audio=false"))
        XCTAssertEqual(MirrorPreferences(defaults: defaults).audioOutput, .phone)
        preferences.mode = .viewOnly; preferences.audioOutput = .computer
        XCTAssertTrue(preferences.configuration.audioEnabled)
        XCTAssertFalse(preferences.configuration.powerOn)
    }
}
