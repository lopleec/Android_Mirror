import CoreMedia
import CoreVideo
import VideoToolbox
import os

/// Used only on the video reader thread. Decode every reference frame; only decoded images may be dropped.
final class HardwareVideoDecoder {
    private var session: VTDecompressionSession?
    private var sourceFormat: CMFormatDescription?
    private var imageFormat: CMVideoFormatDescription?
    private let logger = Logger(subsystem: "com.lopleec.androidmirror", category: "video")

    func decode(_ sample: CMSampleBuffer) throws -> CMSampleBuffer? {
        guard let format = CMSampleBufferGetFormatDescription(sample) else { return nil }
        if sourceFormat == nil || !CMFormatDescriptionEqual(sourceFormat!, otherFormatDescription: format) {
            if let session { VTDecompressionSessionInvalidate(session) }
            session = nil; imageFormat = nil; sourceFormat = format
            let specification = [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true] as CFDictionary
            let attributes = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                              kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
            let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: format,
                decoderSpecification: specification, imageBufferAttributes: attributes,
                outputCallback: nil, decompressionSessionOut: &session)
            guard status == noErr, let session else { throw MirrorError.message(L10n.format("Could not create the video decoder (%d).", status)) }
            VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
            var accelerated: Unmanaged<CFBoolean>?
            VTSessionCopyProperty(session, key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
                                  allocator: kCFAllocatorDefault, valueOut: &accelerated)
            let hardware = accelerated?.takeRetainedValue() == kCFBooleanTrue
            logger.info("Video decoder hardware=\(hardware, privacy: .public)")
        }
        guard let session else { return nil }
        var image: CVImageBuffer?
        var callbackStatus: OSStatus = noErr
        // No async/temporal flags: the callback completes before this call returns (Apple contract).
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) {
            result, _, pixelBuffer, _, _ in callbackStatus = result; image = pixelBuffer
        }
        guard status == noErr, callbackStatus == noErr else {
            throw MirrorError.message(L10n.format("Video decoding failed (%d).", status == noErr ? callbackStatus : status))
        }
        guard let image else { return nil }
        if imageFormat == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
                                                         formatDescriptionOut: &imageFormat)
        }
        guard let imageFormat else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample), decodeTimeStamp: .invalid)
        var output: CMSampleBuffer?
        let result = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
            formatDescription: imageFormat, sampleTiming: &timing, sampleBufferOut: &output)
        guard result == noErr, let output else { throw MirrorError.message(L10n.tr("Could not create the video display buffer.")) }
        H264Decoder.displayImmediately(output)
        return output
    }
    deinit { if let session { VTDecompressionSessionInvalidate(session) } }
}
