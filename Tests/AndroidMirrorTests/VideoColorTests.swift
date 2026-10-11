import XCTest
import CoreMedia
import CoreVideo
@testable import AndroidMirror

final class VideoColorTests: XCTestCase {
    func testLimitedRangeGradientPreservesBlackWhiteAndIntermediateLevels() throws {
        try checkGradient("gradient-limited", pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                          minimum: 16, span: 219, distinctLevels: 210)
    }
    func testFullRangeGradientIsNotRequantizedToLimitedRange() throws {
        try checkGradient("gradient-full", pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                          minimum: 0, span: 255, distinctLevels: 245)
    }
    private func checkGradient(_ name: String, pixelFormat: OSType, minimum: Int, span: Int, distinctLevels: Int) throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "h264", subdirectory: "Fixtures"))
        let encoded = try XCTUnwrap(H264Decoder().consume(Data(contentsOf: url), pts: 1_000))
        let output = try XCTUnwrap(HardwareVideoDecoder().decode(encoded))
        let image = try XCTUnwrap(CMSampleBufferGetImageBuffer(output))
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(image), pixelFormat)
        let format = try XCTUnwrap(CMSampleBufferGetFormatDescription(output))
        XCTAssertTrue(CMVideoFormatDescriptionMatchesImageBuffer(format, imageBuffer: image))
        XCTAssertEqual(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String,
                       kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String)
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        let plane = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(image, 0)).assumingMemoryBound(to: UInt8.self)
        let row = Array(UnsafeBufferPointer(start: plane, count: 256))
        for x in [0, 32, 64, 128, 192, 255] {
            XCTAssertEqual(Double(row[x]), Double(minimum) + Double(span * x) / 255, accuracy: 2)
        }
        XCTAssertGreaterThanOrEqual(Set(row).count, distinctLevels)
    }
    func testColorAttachmentChangesRefreshTheCachedDisplayDescription() throws {
        let encoded = try XCTUnwrap(H264Decoder().consume(Data(contentsOf: XCTUnwrap(
            Bundle.module.url(forResource: "sample", withExtension: "h264", subdirectory: "Fixtures"))), pts: 1_000))
        var pixels: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 32, 32,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &pixels), kCVReturnSuccess)
        let image = try XCTUnwrap(pixels)
        CVBufferSetAttachment(image, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(image, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(image, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        let display = VideoDisplayBuffer()
        let first = try XCTUnwrap(CMSampleBufferGetFormatDescription(display.sample(image: image, source: encoded)))
        CVBufferSetAttachment(image, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_P3_D65, .shouldPropagate)
        CVBufferSetAttachment(image, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
        let second = try XCTUnwrap(CMSampleBufferGetFormatDescription(display.sample(image: image, source: encoded)))
        XCTAssertFalse(CMFormatDescriptionEqual(first, otherFormatDescription: second))
        XCTAssertTrue(CMVideoFormatDescriptionMatchesImageBuffer(second, imageBuffer: image))
        XCTAssertEqual(CMFormatDescriptionGetExtension(second, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String,
                       kCVImageBufferColorPrimaries_P3_D65 as String)
    }
}
