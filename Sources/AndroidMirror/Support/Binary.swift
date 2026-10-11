import Foundation

extension Data {
    mutating func put<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
    func integer<T: FixedWidthInteger>(at offset: Int, as: T.Type = T.self) -> T {
        precondition(offset >= 0 && offset + MemoryLayout<T>.size <= count)
        return self[offset ..< offset + MemoryLayout<T>.size].reduce(T.zero) { ($0 << 8) | T($1) }
    }
}

enum ControlPacket {
    static func key(_ code: UInt32, down: Bool, modifiers: UInt32 = 0) -> Data {
        var data = Data([0, down ? 0 : 1]); data.put(code); data.put(UInt32(0)); data.put(modifiers)
        return data
    }
    static func touch(action: UInt8, x: Int, y: Int, width: Int, height: Int) -> Data {
        var data = Data([2, action]); data.put(UInt64.max - 1)
        data.put(UInt32(clamping: x)); data.put(UInt32(clamping: y))
        data.put(UInt16(clamping: width)); data.put(UInt16(clamping: height))
        data.put(UInt16(action == 1 ? 0 : 65535)); data.put(UInt32(0)); data.put(UInt32(0))
        return data
    }
    static func scroll(x: Int, y: Int, width: Int, height: Int, dx: Double, dy: Double) -> Data {
        var data = Data([3]); data.put(UInt32(clamping: x)); data.put(UInt32(clamping: y))
        data.put(UInt16(clamping: width)); data.put(UInt16(clamping: height))
        data.put(Int16(max(-32768, min(32767, dx / 16 * 32768))))
        data.put(Int16(max(-32768, min(32767, dy / 16 * 32768)))); data.put(UInt32(0))
        return data
    }
    static func clipboard(_ text: String, paste: Bool, sequence: UInt64 = 0) -> Data {
        let bytes = utf8(text, limit: 262130)
        var data = Data([9]); data.put(sequence); data.append(paste ? 1 : 0)
        data.put(UInt32(bytes.count)); data.append(bytes)
        return data
    }
    static func text(_ text: String) -> Data {
        let bytes = utf8(text, limit: 300)
        var data = Data([1]); data.put(UInt32(bytes.count)); data.append(bytes); return data
    }
    static func utf8(_ text: String, limit: Int) -> Data {
        var result = Data()
        for character in text.unicodeScalars {
            let bytes = Array(String(character).utf8)
            guard result.count + bytes.count <= limit else { break }
            result.append(contentsOf: bytes)
        }
        return result
    }
}
