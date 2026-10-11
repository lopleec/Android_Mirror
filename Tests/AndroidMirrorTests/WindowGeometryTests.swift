import XCTest
@testable import AndroidMirror

final class WindowGeometryTests: XCTestCase {
    func testBothDragDirectionsAndScreenClampingPreserveVideoRatio() {
        for video in [CGSize(width: 362, height: 758), CGSize(width: 1080, height: 2400), CGSize(width: 2400, height: 1080)] {
            for proposed in [CGSize(width: 1200, height: 650), CGSize(width: 80, height: 100), CGSize(width: 9000, height: 9000)] {
                for heightDriven in [true, false] {
                    let result = MirrorWindowGeometry.fit(proposed, video: video, limit: CGSize(width: 1400, height: 900), drivenByHeight: heightDriven)
                    XCTAssertEqual((result.width - 12) / (result.height - 42), video.width / video.height, accuracy: 0.000001)
                    XCTAssertLessThanOrEqual(result.width, 1400); XCTAssertLessThanOrEqual(result.height, 900)
                }
            }
        }
    }
    func testSmallDisplayStillPreservesRatio() {
        let size = MirrorWindowGeometry.fit(CGSize(width: 374, height: 800), video: CGSize(width: 1080, height: 2400), limit: CGSize(width: 290, height: 500))
        XCTAssertEqual((size.width - 12) / (size.height - 42), 0.45, accuracy: 0.000001)
        XCTAssertLessThanOrEqual(size.height, 500)
    }
}
