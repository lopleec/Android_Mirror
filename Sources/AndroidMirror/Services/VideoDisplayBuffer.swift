import CoreMedia
import CoreVideo

/// Keep the raster range and color attachments consistent with each displayed image.
/// A limited-range stream is not a limited gamut: never relabel its levels or invent P3/HDR.
final class VideoDisplayBuffer {
    private var format: CMVideoFormatDescription?

    static func pixelFormat(for source: CMFormatDescription) -> OSType {
        let fullRange = CMFormatDescriptionGetExtension(source,
            extensionKey: kCMFormatDescriptionExtension_FullRangeVideo) as? NSNumber
        return fullRange?.boolValue == true
            ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    func sample(image: CVPixelBuffer, source: CMSampleBuffer) throws -> CMSampleBuffer {
        if let encoded = CMSampleBufferGetFormatDescription(source) {
            // VT normally propagates these. Fill omissions from the bitstream only;
            // retain decoder-provided values if it has performed a conversion.
            for key in [kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey,
                        kCVImageBufferYCbCrMatrixKey, kCVImageBufferGammaLevelKey,
                        kCVImageBufferICCProfileKey, kCVImageBufferChromaLocationTopFieldKey,
                        kCVImageBufferChromaLocationBottomFieldKey] {
                if CVBufferCopyAttachment(image, key, nil) == nil,
                   let value = CMFormatDescriptionGetExtension(encoded, extensionKey: key) {
                    CVBufferSetAttachment(image, key, value, .shouldPropagate)
                }
            }
        }
        if format == nil || !CMVideoFormatDescriptionMatchesImageBuffer(format!, imageBuffer: image) {
            format = nil
            let status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                imageBuffer: image, formatDescriptionOut: &format)
            guard status == noErr else {
                throw MirrorError.message(L10n.tr("Could not create the video display buffer."))
            }
        }
        guard let format else { throw MirrorError.message(L10n.tr("Could not create the video display buffer.")) }
        var timing = CMSampleTimingInfo(duration: .invalid,
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(source), decodeTimeStamp: .invalid)
        var output: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &output)
        guard status == noErr, let output else {
            throw MirrorError.message(L10n.tr("Could not create the video display buffer."))
        }
        H264Decoder.displayImmediately(output)
        return output
    }
}
