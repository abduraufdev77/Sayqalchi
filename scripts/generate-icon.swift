import AppKit
import CoreText
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fontURL = root.appendingPathComponent("Sources/Yoz/Resources/Fonts/VoiceLab-Latin.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
let destination = root.appendingPathComponent("packaging/Yoz.iconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
 for scale in [1, 2] {
  let pixels = size * scale
  let image = NSImage(size: NSSize(width: pixels, height: pixels))
  image.lockFocus()
  let p = CGFloat(pixels)
  NSColor(srgbRed: 0, green: 0.867, blue: 0.945, alpha: 1).setFill()
  NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88), xRadius: p * 0.21, yRadius: p * 0.21).fill()
  let font = NSFont(name: "Figtree-Regular", size: p * 0.88) ?? NSFont.systemFont(ofSize: p * 0.88)
  let text = NSAttributedString(string: "y", attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0.106, green: 0.114, blue: 0.106, alpha: 1)])
  let measured = text.size()
  text.draw(at: NSPoint(x: (p - measured.width) / 2, y: (p - measured.height) / 2 + p * 0.055))
  image.unlockFocus()
  let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
  let suffix = scale == 2 ? "@2x" : ""
  try png.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
 }
}
let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor] ?? []
for descriptor in descriptors { print(CTFontDescriptorCopyAttributes(descriptor)) }
