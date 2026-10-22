import AppKit
import CoreText

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fontURL = root.appendingPathComponent("Sources/Yoz/Resources/Fonts/VoiceLab-Latin.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
let destination = root.appendingPathComponent("packaging/Yoz.iconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale, p = CGFloat(pixels)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88)
        let tile = NSBezierPath(roundedRect: rect, xRadius: p * 0.205, yRadius: p * 0.205)
        NSGradient(colors: [color(0xAAA2F8), color(0xEDB4CE), color(0xF5C5A1)])!.draw(in: tile, angle: -45)
        // A quiet highlight keeps the pastel surface soft at large Dock sizes.
        NSGradient(starting: color(0xFFFFFF, alpha: 0.18), ending: color(0xFFFFFF, alpha: 0))!
            .draw(in: tile, angle: -45)
        color(0xFFFFFF, alpha: 0.25).setStroke(); tile.lineWidth = max(0.5, p * 0.0015); tile.stroke()
        let font = NSFont(name: "Figtree-Regular", size: p * 0.77) ?? NSFont.systemFont(ofSize: p * 0.77, weight: .medium)
        let text = NSAttributedString(string: "ö", attributes: [.font: font, .foregroundColor: color(0x29243D)])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let context = NSGraphicsContext.current!.cgContext
        context.textPosition = CGPoint(x: (p - bounds.width) / 2 - bounds.minX,
                                       y: (p - bounds.height) / 2 - bounds.minY - p * 0.006)
        CTLineDraw(line, context)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
print("Generated the gradient ö icon at all macOS icon sizes.")
