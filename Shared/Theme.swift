import SwiftUI

// MARK: - Quiet Glass color tokens

extension Color {
    init(pwHex hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// "Quiet Glass" — OLED-black, one warm-green accent, clay for the exit.
enum PW {
    static let black         = Color(pwHex: 0x000000)
    static let surface       = Color(pwHex: 0x0B0F0B)
    static let surfaceRaised  = Color(pwHex: 0x0C100C)
    static let deepForest    = Color(pwHex: 0x16251A)
    static let moss          = Color(pwHex: 0x5E8C4F)
    static let mossLight     = Color(pwHex: 0x6F9C5E)
    static let sage          = Color(pwHex: 0x9DC47B)   // primary action / accent
    static let dawnGlow      = Color(pwHex: 0xBCE890)   // brightest accent
    static let clay          = Color(pwHex: 0xC8A27B)   // escape-hatch / destructive
    static let textPrimary   = Color(pwHex: 0xECF1E6)
    static let textMuted     = Color(pwHex: 0x8E9A86)
    static let textFaint     = Color(pwHex: 0x5A6356)
    static let textFaintest  = Color(pwHex: 0x4A5247)
    static let warn          = Color(pwHex: 0x9A6A6A)   // the one red-ish warning line
    static let onAccent      = Color(pwHex: 0x0A140B)   // text/icon on a sage button
    static let encourage     = Color(pwHex: 0xA9B5A1)   // poetic lines

    static let hairline      = Color.white.opacity(0.07)
    static let separator     = Color.white.opacity(0.06)
}

// MARK: - Typography (Spectral + Schibsted Grotesk)

extension Font {
    /// Spectral Light — display headings and every poetic/encouragement line.
    static func spectral(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "Spectral-LightItalic" : "Spectral-Light", size: size)
    }

    /// Schibsted Grotesk (variable) — all interface text. Weight interpolates.
    static func grotesk(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("SchibstedGrotesk-Regular", size: size).weight(weight)
    }
}

// MARK: - Shared view helpers

extension View {
    /// Uppercase section label in the faint tracked style above grouped cards.
    func pwSectionLabel() -> some View {
        self.font(.grotesk(11, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(PW.textFaint)
            .textCase(.uppercase)
    }
}
