import SwiftUI

/**
 * Look of the McSkill launcher, the same values as the Android app (ui/Theme.java): near-black
 * background with a teal glow at the top, dark cards with hairline borders, teal accent, gold for
 * favourites, Inter everywhere. Android dp/sp map 1:1 to points.
 */
enum Theme {
    static let bg = Color(hex: 0x121214)
    static let glow = Color(hex: 0x0E2E33)
    static let card = Color(hex: 0x1F1F22)
    static let cardBorder = Color(hex: 0x2A2B30)
    static let panel = Color(hex: 0x1F2024)
    static let panelBorder = Color(hex: 0x2C2D31)
    static let tile = Color(hex: 0x262629)
    static let field = Color(hex: 0x17171A)
    static let fieldBorder = Color(hex: 0x303136)

    static let accent = Color(hex: 0x3DA8B8)
    static let accentLight = Color(hex: 0x39A6B6)
    static let accentDark = Color(hex: 0x03849C)
    static let gold = Color(hex: 0xFFB800)
    static let goldBorder = Color(argb: 0x99FFB800)
    static let wipe = Color(hex: 0xE5A54B)
    static let green = Color(hex: 0x22C55E)
    static let red = Color(hex: 0xEF4444)
    static let blue = Color(hex: 0x60A5FA)

    static let text = Color.white
    static let text2 = Color(hex: 0x8B8B90)
    static let text3 = Color(hex: 0x6B6B70)
    static let chipText = Color(hex: 0xD4D4D4)

    static let tileTeal = Color(hex: 0x28353A)
    static let tileRed = Color(hex: 0x3E292C)
    static let tileGreen = Color(hex: 0x25392F)
    static let tileGold = Color(hex: 0x3A3322)

    /** Left-to-right teal gradient of the play button. */
    static let accentGradient = LinearGradient(colors: [accentLight, accentDark], startPoint: .leading, endPoint: .trailing)

    static func regular(_ size: CGFloat) -> Font { .custom("Inter-Regular", fixedSize: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("Inter-Medium", fixedSize: size) }
    static func semibold(_ size: CGFloat) -> Font { .custom("Inter-SemiBold", fixedSize: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("Inter-Bold", fixedSize: size) }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /** Android's 0xAARRGGBB. */
    init(argb: UInt32) {
        self.init(hex: argb & 0xFFFFFF, opacity: Double((argb >> 24) & 0xFF) / 255)
    }
}

extension String {
    /** Uppercase the way the launcher's labels are. */
    var caps: String { uppercased(with: Locale(identifier: "ru")) }
}

extension View {
    /** Rounded fill with an optional hairline border: Ui.rounded() of the Android app. */
    func box(_ fill: Color, radius: CGFloat, border: Color? = nil) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay {
                if let border { RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1) }
            }
    }

    /** Dark card of the details panel (Ui.card). */
    func panelCard() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .box(Theme.panel, radius: 12, border: Theme.panelBorder)
    }
}

/**
 * Root background, "Фоновое свечение": a wide, flat teal ellipse centred above the top edge, a
 * little left of centre like the PC launcher (GlowLayout).
 */
struct GlowBackground: View {
    var glow = true

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.bg))
            guard glow, size.width > 0 else { return }
            let radius = size.width * 0.5
            ctx.translateBy(x: size.width * 0.48, y: -size.height * 0.04)
            ctx.scaleBy(x: 1, y: min(1, size.height * 0.55 / radius))
            let gradient = Gradient(stops: [
                .init(color: Theme.glow, location: 0),
                .init(color: Color(argb: 0x990E2E33), location: 0.45),
                .init(color: Color(argb: 0x00121214), location: 1),
            ])
            ctx.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                     with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: radius))
        }
        .ignoresSafeArea()
    }
}
