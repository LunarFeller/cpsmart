import AppKit

/// 应用共享的颜色与圆角 token。浮窗、设置页和关于页应从这里取值，避免各自形成一套风格。
struct Palette {
    let accent: NSColor
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor
    let cardFill: NSColor
    let cardFillHover: NSColor
    let cardFillSelected: NSColor
    let cardBorder: NSColor
    let panelBorder: NSColor
    let panelTint: NSColor
    let thumbPlaceholder: NSColor
    let typeText: NSColor
    let typeImage: NSColor
    let typeFile: NSColor

    func pinboardColor(_ color: PinboardColor) -> NSColor {
        switch color {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .gray: return .systemGray
        }
    }
}

enum AppVisualTheme {
    static let panelRadius: CGFloat = 20
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 9

    static func palette(isDark: Bool) -> Palette {
        if isDark {
            let accent = NSColor(srgbRed: 10 / 255, green: 132 / 255, blue: 255 / 255, alpha: 1)
            return Palette(
                accent: accent,
                textPrimary: NSColor.white.withAlphaComponent(0.92),
                textSecondary: NSColor.white.withAlphaComponent(0.55),
                textTertiary: NSColor.white.withAlphaComponent(0.38),
                cardFill: NSColor.white.withAlphaComponent(0.055),
                cardFillHover: NSColor.white.withAlphaComponent(0.09),
                cardFillSelected: accent.withAlphaComponent(0.16),
                cardBorder: NSColor.white.withAlphaComponent(0.10),
                panelBorder: NSColor.white.withAlphaComponent(0.16),
                panelTint: NSColor(srgbRed: 0.055, green: 0.065, blue: 0.085, alpha: 0.78),
                thumbPlaceholder: NSColor.white.withAlphaComponent(0.045),
                typeText: NSColor(srgbRed: 0.35, green: 0.78, blue: 0.98, alpha: 1),
                typeImage: NSColor(srgbRed: 0.72, green: 0.55, blue: 0.98, alpha: 1),
                typeFile: NSColor(srgbRed: 0.98, green: 0.72, blue: 0.32, alpha: 1)
            )
        }
        let accent = NSColor(srgbRed: 0, green: 122 / 255, blue: 1, alpha: 1)
        return Palette(
            accent: accent,
            textPrimary: NSColor.black.withAlphaComponent(0.86),
            textSecondary: NSColor.black.withAlphaComponent(0.56),
            textTertiary: NSColor.black.withAlphaComponent(0.42),
            cardFill: NSColor.black.withAlphaComponent(0.045),
            cardFillHover: NSColor.black.withAlphaComponent(0.075),
            cardFillSelected: accent.withAlphaComponent(0.14),
            cardBorder: NSColor.black.withAlphaComponent(0.10),
            panelBorder: NSColor.black.withAlphaComponent(0.12),
            panelTint: NSColor.white.withAlphaComponent(0.72),
            thumbPlaceholder: NSColor.black.withAlphaComponent(0.05),
            typeText: NSColor(srgbRed: 0.03, green: 0.50, blue: 0.70, alpha: 1),
            typeImage: NSColor(srgbRed: 0.55, green: 0.32, blue: 0.82, alpha: 1),
            typeFile: NSColor(srgbRed: 0.80, green: 0.52, blue: 0.05, alpha: 1)
        )
    }
}
