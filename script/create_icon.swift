import AppKit
import ImageIO
import UniformTypeIdentifiers

// Format the supplied PNG using the actual system-rendered silhouette at each output size.
// Only the system icon's alpha outline and neutral shadow are used, never its artwork.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift script/create_icon.swift source.png output.png")
}
func canvas(_ pixels: Int) -> CGContext {
    CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let decoder = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(decoder, 0, nil) else { fatalError("Cannot read the original PNG") }
let reference = NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app")
func template(_ pixels: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    reference.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
let masterTemplate = template(1024)
let masterPixels = masterTemplate.bitmapData!
var minX = 1024, minY = 1024, maxX = 0, maxY = 0
for y in 0..<1024 {
    for x in 0..<1024 where masterPixels[(y * 1024 + x) * 4 + 3] >= 128 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
let background = NSBitmapImageRep(cgImage: original).colorAt(x: 0, y: 0)!
    .usingColorSpace(.sRGB)!.withAlphaComponent(1).cgColor
func render(_ pixels: Int) -> CGImage {
    let systemMask = pixels == 1024 ? masterTemplate : template(pixels)
    let mask = systemMask.bitmapData!
    let artwork = canvas(pixels)
    let full = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    let scale = CGFloat(pixels) / 1024
    artwork.setFillColor(background); artwork.fill(full)
    artwork.interpolationQuality = .high
    artwork.draw(original, in: CGRect(x: bounds.minX * scale, y: bounds.minY * scale,
                                     width: bounds.width * scale, height: bounds.height * scale))
    let result = canvas(pixels)
    let input = artwork.data!.assumingMemoryBound(to: UInt8.self)
    let output = result.data!.assumingMemoryBound(to: UInt8.self)
    for index in 0..<(pixels * pixels) {
        let offset = index * 4
        let alpha = Int(mask[offset + 3])
        // Preserve the native black shadow outside the tile, not a gray glow around its corners.
        let darkShadow = alpha < 128 && max(Int(mask[offset]), Int(mask[offset + 1]), Int(mask[offset + 2])) * 255 < alpha * 100
        for channel in 0..<3 {
            output[offset + channel] = darkShadow ? 0 : UInt8((Int(input[offset + channel]) * alpha + 127) / 255)
        }
        output[offset + 3] = UInt8(alpha)
        precondition(output[offset + 3] == mask[offset + 3])
    }
    return result.makeImage()!
}
func writePNG(_ image: CGImage, to url: URL) {
    let encoder = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(encoder, image, nil)
    precondition(CGImageDestinationFinalize(encoder), "Cannot save PNG")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
writePNG(render(1024), to: destination)
let iconset = destination.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for multiplier in [1, 2] {
        let pixels = size * multiplier
        let suffix = multiplier == 2 ? "@2x" : ""
        writePNG(render(pixels), to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let compiler = Process()
compiler.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
compiler.arguments = ["-c", "icns", iconset.path, "-o", destination.deletingLastPathComponent().appendingPathComponent("AppIcon.icns").path]
try compiler.run(); compiler.waitUntilExit()
precondition(compiler.terminationStatus == 0)
print("System-rendered silhouette matched at every size; 1024px body bounds: \(bounds)")
