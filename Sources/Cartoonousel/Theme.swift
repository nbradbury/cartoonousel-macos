import AppKit
import CoreText
import SwiftUI

/// Colours, type and small shared view pieces from the Cartoonousel design.
enum Theme {
    static let ink = Color(hex: 0x121212)
    static let paper = Color(hex: 0xF3F1EC)
    static let card = Color(hex: 0xFBFAF7)
    static let hatchDark = Color(hex: 0xE9E7E1)
    static let hatchLight = Color(hex: 0xF8F7F3)

    static let displayFamily = "Bricolage Grotesque"
    static let monoFamily = "JetBrains Mono"

    /// Bricolage Grotesque (falls back to SF Pro).
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        if let font = familyFont(displayFamily, size: size, weight: weight) { return font }
        return .system(size: size, weight: weight)
    }

    /// JetBrains Mono (falls back to SF Mono).
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let font = familyFont(monoFamily, size: size, weight: weight) { return font }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    /// CSS `clamp(min, vw * fraction, max)`.
    static func clamp(_ lo: CGFloat, _ value: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(hi, max(lo, value))
    }

    // MARK: - Font resolution

    private static var cache: [String: Font] = [:]
    private static var installedFamilies = Set(NSFontManager.shared.availableFontFamilies)

    private static func familyFont(_ family: String, size: CGFloat, weight: Font.Weight) -> Font? {
        guard installedFamilies.contains(family) else { return nil }
        let key = "\(family)|\(size)|\(weight)"
        if let hit = cache[key] { return hit }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: nsWeight(weight).rawValue],
        ])
        guard let nsFont = NSFont(descriptor: descriptor, size: size) else { return nil }
        let font = Font(nsFont as CTFont)
        cache[key] = font
        return font
    }

    private static func nsWeight(_ w: Font.Weight) -> NSFont.Weight {
        switch w {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    /// Registers any .ttf/.otf files bundled in Resources/Fonts. Call once at launch.
    static func registerBundledFonts() {
        guard let dir = Bundle.module.url(forResource: "Fonts", withExtension: nil),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in urls where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        installedFamilies = Set(NSFontManager.shared.availableFontFamilies)
        cache.removeAll()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// CSS `repeating-linear-gradient(135deg, dark 0 s, light s 2s)` — diagonal "/" hatching.
struct Hatch: View {
    var stripe: CGFloat = 7

    var body: some View {
        Canvas { gc, size in
            gc.clip(to: Path(CGRect(origin: .zero, size: size)))
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.hatchLight))
            let diag = size.width + size.height
            gc.translateBy(x: size.width / 2, y: size.height / 2)
            gc.rotate(by: .degrees(45))
            var x = -diag
            var bands = Path()
            while x < diag {
                bands.addRect(CGRect(x: x, y: -diag, width: stripe, height: diag * 2))
                x += stripe * 2
            }
            gc.fill(bands, with: .color(Theme.hatchDark))
        }
    }
}

/// Square-cornered ink buttons that invert on hover.
struct InkButtonStyle: ButtonStyle {
    var filled = false
    var fontSize: CGFloat = 12
    var hPad: CGFloat = 13
    var vPad: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        InkButtonBody(configuration: configuration, style: self)
    }

    private struct InkButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let style: InkButtonStyle
        @State private var hovering = false

        var body: some View {
            // Filled buttons go light on hover; light buttons go dark.
            let dark = style.filled != hovering
            configuration.label
                .font(Theme.mono(style.fontSize, weight: .semibold))
                .tracking(style.fontSize * 0.05)
                .textCase(.uppercase)
                .foregroundStyle(dark ? Theme.paper : Theme.ink)
                .padding(.horizontal, style.hPad + 2) // CSS border sits outside the padding
                .padding(.vertical, style.vPad + 2)
                .background(dark ? Theme.ink : Theme.paper)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
                .opacity(configuration.isPressed ? 0.85 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// "Title  ⌘O" label used on the header and empty-state buttons.
struct ShortcutLabel: View {
    let title: String
    var shortcut: String?
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            if let shortcut {
                Text(shortcut).font(Theme.mono(size, weight: .regular))
            }
        }
    }
}
