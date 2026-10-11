import Foundation
import CoreMedia

/// Turns scrcpy's Annex B packets into AVCC samples for Apple's hardware decoder.
final class H264Decoder {
    private var sps: [UInt8] = []
    private var pps: [UInt8] = []
    private(set) var format: CMVideoFormatDescription?

    static func units(_ data: Data) -> [Data] {
        let bytes = Array(data)
        var starts: [(start: Int, payload: Int)] = []
        var index = 0
        while index + 2 < bytes.count {
            if bytes[index] == 0 && bytes[index + 1] == 0 {
                if bytes[index + 2] == 1 {
                    starts.append((index, index + 3)); index += 3; continue
                }
                if index + 3 < bytes.count && bytes[index + 2] == 0 && bytes[index + 3] == 1 {
                    starts.append((index, index + 4)); index += 4; continue
                }
            }
            index += 1
        }
        return starts.enumerated().compactMap { offset, marker in
            let end = offset + 1 < starts.count ? starts[offset + 1].start : bytes.count
            guard end > marker.payload else { return nil }
            return Data(bytes[marker.payload..<end])
        }
    }

    func consume(_ packet: Data, pts: UInt64) throws -> CMSampleBuffer? {
        let units = Self.units(packet)
        var changed = false
        var payload = Data()
        for unit in units {
            guard let first = unit.first else { continue }
            switch first & 31 {
            case 7: sps = Array(unit); changed = true
            case 8: pps = Array(unit); changed = true
            default: payload.put(UInt32(unit.count)); payload.append(unit)
            }
        }
        if changed && !sps.isEmpty && !pps.isEmpty {
            var description: CMFormatDescription?
            let status = sps.withUnsafeBufferPointer { spsBytes in
                pps.withUnsafeBufferPointer { ppsBytes in
                    let pointers = [spsBytes.baseAddress!, ppsBytes.baseAddress!]
                    let sizes = [sps.count, pps.count]
                    return pointers.withUnsafeBufferPointer { pointer in
                        sizes.withUnsafeBufferPointer { size in
                            CMVideoFormatDescriptionCreateFromH264ParameterSets(
                                allocator: kCFAllocatorDefault, parameterSetCount: 2,
                                parameterSetPointers: pointer.baseAddress!, parameterSetSizes: size.baseAddress!,
                                nalUnitHeaderLength: 4, formatDescriptionOut: &description)
                        }
                    }
                }
            }
            guard status == noErr else { throw MirrorError.message(L10n.format("Could not parse phone video parameters (%d).", status)) }
            format = description
        }
        guard !payload.isEmpty, let format else { return nil }
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: payload.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: payload.count, flags: 0, blockBufferOut: &block)
        guard status == noErr, let block else { throw MirrorError.message(L10n.tr("Could not create a video buffer.")) }
        status = payload.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: payload.count)
        }
        guard status == noErr else { throw MirrorError.message(L10n.tr("Could not write the video buffer.")) }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid,
            presentationTimeStamp: CMTime(value: Int64(pts), timescale: 1_000_000), decodeTimeStamp: .invalid)
        var size = payload.count
        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw MirrorError.message(L10n.tr("Could not create a video frame.")) }
        Self.displayImmediately(sample)
        return sample
    }
    static func displayImmediately(_ sample: CMSampleBuffer) {
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
    }
}
