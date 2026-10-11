import XCTest
import CoreMedia
import VideoToolbox
import AVFoundation
@testable import AndroidMirror

final class VideoTests: XCTestCase {
    @MainActor func testBusyMainThreadKeepsOnlyLatestDecodedFrameAndStopRejectsOldSession() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "h264", subdirectory: "Fixtures"))
        let units = H264Decoder.units(try Data(contentsOf: url))
        let frameUnits = units.prefix(while: { $0[0] & 31 != 1 })
        let packet = frameUnits.reduce(into: Data()) { result, unit in
            result.append(contentsOf: [0, 0, 0, 1]); result.append(unit)
        }
        let sample = try XCTUnwrap(H264Decoder().consume(packet, pts: 1_000))
        let decoded = try XCTUnwrap(HardwareVideoDecoder().decode(sample))
        let layer = AVSampleBufferDisplayLayer()
        var displayedSizes: [CGSize] = []
        let presenter = VideoFramePresenter(layer: layer) { displayedSizes.append($0) }
        // Simulate 200 arrivals while the UI thread cannot drain. Only the newest image is useful.
        for index in 1...200 { presenter.offer(decoded, size: CGSize(width: index, height: 640)) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(displayedSizes, [CGSize(width: 200, height: 640)])
        presenter.stop()
        presenter.offer(decoded, size: CGSize(width: 999, height: 640))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(displayedSizes.count, 1)
    }
    func testAnnexBProducesDecodableAppleVideoSamples() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "h264", subdirectory: "Fixtures"))
        let stream = try Data(contentsOf: url)
        let decoder = H264Decoder()
        let units = H264Decoder.units(stream)
        let configuration = units.filter { [7, 8].contains(Int($0[0] & 31)) }
        let firstFrame = units.prefix(while: { $0[0] & 31 != 1 }).filter { ![7, 8].contains(Int($0[0] & 31)) }
        func annexB(_ units: [Data]) -> Data {
            units.reduce(into: Data()) { data, unit in data.append(contentsOf: [0, 0, 0, 1]); data.append(unit) }
        }
        XCTAssertNil(try decoder.consume(annexB(configuration), pts: 0))
        let sample = try XCTUnwrap(decoder.consume(annexB(firstFrame), pts: 1_000))
        let format = try XCTUnwrap(decoder.format)
        XCTAssertEqual(CMVideoFormatDescriptionGetDimensions(format).width, 320)
        XCTAssertEqual(CMVideoFormatDescriptionGetDimensions(format).height, 640)
        XCTAssertEqual(CMSampleBufferGetNumSamples(sample), 1)
        let backgroundDecoder = HardwareVideoDecoder()
        let displayed = try XCTUnwrap(backgroundDecoder.decode(sample))
        let pixels = try XCTUnwrap(CMSampleBufferGetImageBuffer(displayed))
        XCTAssertEqual(CVPixelBufferGetWidth(pixels), 320)
        XCTAssertEqual(CVPixelBufferGetHeight(pixels), 640)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixels), kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: format,
            decoderSpecification: nil, imageBufferAttributes: nil, outputCallback: nil, decompressionSessionOut: &session)
        XCTAssertEqual(status, noErr)
        let decoderSession = try XCTUnwrap(session)
        defer { VTDecompressionSessionInvalidate(decoderSession) }
        let decoded = expectation(description: "Apple decoder produced a pixel buffer")
        let result = VTDecompressionSessionDecodeFrame(decoderSession, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { status, _, image, _, _ in
            XCTAssertEqual(status, noErr)
            XCTAssertNotNil(image)
            if let image {
                XCTAssertEqual(CVPixelBufferGetWidth(image), 320)
                XCTAssertEqual(CVPixelBufferGetHeight(image), 640)
            }
            decoded.fulfill()
        }
        XCTAssertEqual(result, noErr)
        XCTAssertEqual(VTDecompressionSessionWaitForAsynchronousFrames(decoderSession), noErr)
        wait(for: [decoded], timeout: 3)
    }
    func testConfigurationChangeUpdatesRotationDimensions() throws {
        let decoder = H264Decoder()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "h264", subdirectory: "Fixtures"))
        let source = try Data(contentsOf: url)
        _ = try decoder.consume(source, pts: 0)
        XCTAssertEqual(CMVideoFormatDescriptionGetDimensions(try XCTUnwrap(decoder.format)).height, 640)
        let landscape = try XCTUnwrap(Bundle.module.url(forResource: "landscape", withExtension: "h264", subdirectory: "Fixtures"))
        _ = try decoder.consume(Data(contentsOf: landscape), pts: 1_000)
        let dimensions = CMVideoFormatDescriptionGetDimensions(try XCTUnwrap(decoder.format))
        XCTAssertEqual(dimensions.width, 640)
        XCTAssertEqual(dimensions.height, 320)
    }
}
