import SwiftUI

/// Canonical design tokens — single source of truth for the palette and
/// type ramp. View-local color constants must alias these instead of
/// declaring their own `Color(red:green:blue:)` literals.
enum Theme {
    // MARK: - Palette

    /// App background (deep felt green).
    static let bg = Color(red: 0.08, green: 0.12, blue: 0.08)
    /// Darkest background, used at the bottom of radial gradients.
    static let bgDeep = Color(red: 0.05, green: 0.09, blue: 0.06)
    /// Lit top of the atmospheric radial gradient.
    static let bgGlow = Color(red: 0.14, green: 0.22, blue: 0.15)

    /// Brand gold — accents, primary text highlights, gold player.
    static let gold = Color(red: 0.92, green: 0.78, blue: 0.45)
    static let goldBright = Color(red: 0.98, green: 0.85, blue: 0.52)
    static let goldDeep = Color(red: 0.82, green: 0.65, blue: 0.32)

    /// Red player + destructive accents. 3.6:1 on bg — large text/UI only.
    static let red = Color(red: 0.82, green: 0.22, blue: 0.20)
    /// Error message text — 4.5:1+ on bg, safe at body sizes.
    static let errorText = Color(red: 0.95, green: 0.45, blue: 0.42)

    /// Brand green — secondary actions, connected status.
    static let green = Color(red: 0.0, green: 0.55, blue: 0.32)
    /// Green for small text on dark backgrounds (the button green fails
    /// contrast below 18pt).
    static let greenBright = Color(red: 0.2, green: 0.7, blue: 0.42)

    static let cream = Color(red: 0.96, green: 0.94, blue: 0.88)

    // MARK: - Text emphasis (legibility floor: tertiary = 5.9:1 on bg)

    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.7)
    static let textTertiary = Color.white.opacity(0.55)

    // MARK: - Shared gradients

    static var goldGradient: LinearGradient {
        LinearGradient(colors: [goldBright, goldDeep], startPoint: .top, endPoint: .bottom)
    }

    static var bgGradient: RadialGradient {
        RadialGradient(colors: [bgGlow, bgDeep], center: .top, startRadius: 80, endRadius: 600)
    }

    // MARK: - Type ramp (Georgia with Dynamic Type)

    /// Sizes below 11pt are bumped to the iOS legibility floor; every font
    /// scales with the user's Dynamic Type setting via `relativeTo:`.
    static func serif(_ size: CGFloat) -> Font {
        .custom("Georgia", size: max(size, 11), relativeTo: bucket(size))
    }

    static func serifBold(_ size: CGFloat) -> Font {
        .custom("Georgia-Bold", size: max(size, 11), relativeTo: bucket(size))
    }

    static func serifItalic(_ size: CGFloat) -> Font {
        .custom("Georgia-Italic", size: max(size, 11), relativeTo: bucket(size))
    }

    private static func bucket(_ size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: return .caption2
        case ..<14: return .caption
        case ..<16: return .footnote
        case ..<18: return .body
        case ..<22: return .title3
        case ..<30: return .title2
        case ..<40: return .title
        default: return .largeTitle
        }
    }
}
