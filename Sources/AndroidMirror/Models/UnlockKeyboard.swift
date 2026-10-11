import Foundation

enum UnlockInputMethod: String, CaseIterable, Identifiable {
    case physical, compatibility
    var id: String { rawValue }
    var title: String { self == .physical ? L10n.tr("Physical Keyboard · US") : L10n.tr("Compatibility Input") }
}

/// A standard USB boot keyboard over scrcpy's UHID control messages (v3.3.4).
/// Credentials only travel through the existing control socket, never ADB arguments or clipboard.
enum UnlockKeyboard {
    static let id: UInt16 = 1
    static let descriptor = Data([
        0x05, 0x01, 0x09, 0x06, 0xa1, 0x01, 0x05, 0x07,
        0x19, 0xe0, 0x29, 0xe7, 0x15, 0x00, 0x25, 0x01,
        0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x75, 0x08,
        0x95, 0x01, 0x81, 0x01, 0x05, 0x08, 0x19, 0x01,
        0x29, 0x05, 0x75, 0x01, 0x95, 0x05, 0x91, 0x02,
        0x75, 0x03, 0x95, 0x01, 0x91, 0x01, 0x05, 0x07,
        0x19, 0x00, 0x29, 0x65, 0x15, 0x00, 0x25, 0x65,
        0x75, 0x08, 0x95, 0x06, 0x81, 0x00, 0xc0
    ])
    static func create() -> Data {
        let name = Data("Android Mirror Keyboard".utf8)
        var packet = Data([12]); packet.put(id)
        packet.put(UInt16(0)); packet.put(UInt16(0))
        packet.append(UInt8(name.count)); packet.append(name)
        packet.put(UInt16(descriptor.count)); packet.append(descriptor)
        return packet
    }
    static func destroy() -> Data { var packet = Data([14]); packet.put(id); return packet }
    static func report(usage: UInt8 = 0, modifiers: UInt8 = 0) -> Data {
        var packet = Data([13]); packet.put(id); packet.put(UInt16(8))
        packet.append(contentsOf: [modifiers, 0, usage, 0, 0, 0, 0, 0])
        return packet
    }
    static func supports(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 128 && text.utf8.allSatisfy { (32...126).contains($0) }
    }
    static func strokes(for text: String) -> [Data]? {
        guard supports(text) else { return nil }
        var packets: [Data] = []
        for character in text.utf8 {
            guard let (usage, modifiers) = key(character) else { return nil }
            packets.append(report(usage: usage, modifiers: modifiers)); packets.append(report())
        }
        // One explicit submission; never retry a password automatically.
        packets.append(report(usage: 0x28)); packets.append(report())
        return packets
    }
    private static func key(_ ascii: UInt8) -> (UInt8, UInt8)? {
        if (97...122).contains(ascii) { return (ascii - 97 + 4, 0) }
        if (65...90).contains(ascii) { return (ascii - 65 + 4, 2) }
        if let index = Array("1234567890".utf8).firstIndex(of: ascii) { return (UInt8(index) + 0x1e, 0) }
        if let index = Array("!@#$%^&*()".utf8).firstIndex(of: ascii) { return (UInt8(index) + 0x1e, 2) }
        let symbols: [(String, UInt8)] = [("-_", 0x2d), ("=+", 0x2e), ("[{", 0x2f), ("]}", 0x30),
                                         ("\\|", 0x31), (";:", 0x33), ("'\"", 0x34), ("`~", 0x35),
                                         (",<", 0x36), (".>", 0x37), ("/?", 0x38)]
        for (pair, usage) in symbols {
            if let index = Array(pair.utf8).firstIndex(of: ascii) { return (usage, index == 0 ? 0 : 2) }
        }
        return ascii == 32 ? (0x2c, 0) : nil
    }
}
