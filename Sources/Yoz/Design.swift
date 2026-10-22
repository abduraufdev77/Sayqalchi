import SwiftUI
import CoreText

enum Design {
    static let ink = Color(hex: 0x1B1D1B)
    static let muted = Color(hex: 0x747873)
    static let paper = Color(hex: 0xF8F8F4)
    static let line = Color(hex: 0xE5E7E0)
    static let cyan = Color(hex: 0x00DDF1)
    static let green = Color(hex: 0x91EF57)
    static let orange = Color(hex: 0xFF743D)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Figtree-Regular", size: size).weight(weight) }
    static func registerFonts() {
        // SwiftPM's generated Bundle.module points beside the .app. Resolve installed
        // resources explicitly so the app never depends on the developer's build folder.
        let installed = Bundle.main.resourceURL?.appendingPathComponent("Yoz_Yoz.bundle/Resources/Fonts")
        let fonts: URL
        if let installed, FileManager.default.fileExists(atPath: installed.path) { fonts = installed }
        else { fonts = Bundle.module.resourceURL!.appendingPathComponent("Resources/Fonts") }
        for name in ["VoiceLab-Latin", "VoiceLab-Cyrillic"] {
            let url = fonts.appendingPathComponent("\(name).ttf")
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}

struct ActionButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = Design.ink
    var textColor: Color = .white
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { Text(title); if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) } }
                .font(Design.font(13, .semibold)).padding(.horizontal, 19).frame(height: 40)
                .foregroundStyle(textColor).background(color, in: Capsule())
        }.buttonStyle(PointerButtonStyle())
    }
}

struct YozMark: View {
    var size: CGFloat = 34
    var body: some View {
        Text("y").font(Design.font(size * 0.94, .semibold)).offset(y: -size * 0.08)
            .frame(width: size, height: size).foregroundStyle(Design.ink)
            .background(Design.cyan, in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased()).font(Design.font(10, .semibold)).tracking(2).foregroundStyle(Design.muted)
            Text(title).font(Design.font(38)).tracking(-1.3)
            Text(subtitle).font(Design.font(14)).foregroundStyle(Design.muted).lineSpacing(4)
        }
    }
}

/// Balance cursor pushes even when an animated tab removes its hovered control.
struct PointerCursor: ViewModifier {
    @State private var inside = false
    func body(content: Content) -> some View {
        content.onHover { hovering in
            guard hovering != inside else { return }
            inside = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }.onDisappear { if inside { NSCursor.pop(); inside = false } }
    }
}
extension View {
    func pointerCursor() -> some View { modifier(PointerCursor()) }
}
struct PointerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : enabled ? 1 : 0.45)
            .contentShape(Rectangle()).pointerCursor()
    }
}
