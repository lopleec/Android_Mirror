import XCTest
@testable import AndroidMirror

final class LocalizationTests: XCTestCase {
    func testExplicitLanguagesResolveUIAndBackgroundErrors() {
        XCTAssertEqual(L10n.tr("Connect", language: "en"), "Connect")
        XCTAssertEqual(L10n.tr("Connect", language: "zh-Hans"), "连接")
        XCTAssertEqual(L10n.tr("Settings…", language: "en"), "Settings…")
        XCTAssertEqual(L10n.tr("Settings…", language: "zh-Hans"), "设置…")
        XCTAssertEqual(L10n.tr("The phone connection was interrupted. Check Wireless debugging or USB.", language: "en"), "The phone connection was interrupted. Check Wireless debugging or USB.")
        XCTAssertNotEqual(L10n.tr("The phone connection was interrupted. Check Wireless debugging or USB.", language: "zh-Hans"), L10n.tr("The phone connection was interrupted. Check Wireless debugging or USB.", language: "en"))
    }
    func testFallbackAndFormatArgumentsDoNotLoseDynamicData() {
        XCTAssertEqual(L10n.tr("Unknown future key", language: "en"), "Unknown future key")
        for language in ["en", "zh-Hans"] {
            XCTAssertTrue(String(format: L10n.tr("Delete “%@”?", language: language), "My Phone").contains("My Phone"))
            XCTAssertTrue(String(format: L10n.tr("Keychain operation failed (%d). Try Mac authentication again.", language: language), -50).contains("-50"))
            XCTAssertTrue(String(format: L10n.tr("%ld minutes", language: language), 10).contains("10"))
            XCTAssertNotNil(AppResources.url(for: "Guide-\(language)", extension: "html"))
        }
    }
}
