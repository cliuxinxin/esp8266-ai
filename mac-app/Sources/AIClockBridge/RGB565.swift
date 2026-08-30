import AppKit
import Foundation

/// Shared CGContext → device wire-format conversion for Mac-rendered pages.
/// The firmware draws full-screen pages (quote, weather strips, the composite
/// "NOW" page) from RGB565 bytes with big-endian byte order, and the menu-bar
/// mirror re-decodes the same bytes — so one converter keeps the device bitmap
/// and the preview identical.
enum RGB565 {
    /// Encode a premultipliedLast RGBA context (rows top-down, as produced by
    /// QuotePageLayout / NowPageLayout) into `width * height * 2` bytes of
    /// big-endian RGB565. Returns all-zero bytes if the context has no data.
    static func encode(from context: CGContext, width: Int, height: Int) -> Data {
        guard let rendered = context.data else { return Data(count: width * height * 2) }
        let pixels = rendered.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var output = Data(capacity: width * height * 2)
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            let value = (UInt16(pixels[offset] & 0xF8) << 8)
                | (UInt16(pixels[offset + 1] & 0xFC) << 3)
                | UInt16(pixels[offset + 2] >> 3)
            output.append(UInt8(value >> 8))
            output.append(UInt8(value & 0xFF))
        }
        return output
    }
}