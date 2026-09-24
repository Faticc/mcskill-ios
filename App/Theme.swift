import SwiftUI

/**
 * Look of the McSkill launcher, same values as the Android app (ui/Theme.java): near-black
 * background with a teal glow at the top, dark cards with hairline borders, teal accent.
 */
enum Theme {
    static let bg = Color(hex: 0x121214)
    static let glow = Color(hex: 0x0E2E33)
    static let card = Color(hex: 0x1F1F22)
    static let cardBorder = Color(hex: 0x2A2B30)
    static let panel = Color(hex: 0x1F2024)
    static let tile = Color(hex: 0x262629)
    static let field = Color(hex: 0x17171A)
    static let fieldBorder = Color(hex: 0x303136)

    static let accent = Color(hex: 0x3DA8B8)
    static let accentLight = Color(hex: 0x39A6B6)
    static let accentDark = Color(hex: 0x03849C)
    static let gold = Color(hex: 0xFFB800)
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
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg
            RadialGradient(colors: [Theme.glow, Theme.bg.opacity(0)], center: .top,
                           startRadius: 0, endRadius: 420)
                .frame(height: 420)
        }
        .ignoresSafeArea()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .textCase(.uppercase)
            .kerning(0.8)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Theme.accentLight, Theme.accentDark],
                                         startPoint: .top, endPoint: .bottom))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension View {
    func card(fill: Color = Theme.card, border: Color = Theme.cardBorder, radius: CGFloat = 12) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(border, lineWidth: 1))
    }
}

/** Text field with an icon, as on the McSkill login card. */
struct Field: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.text3)
                .frame(width: 18)
            Group {
                if secure {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.text3))
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.text3))
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .card(fill: Theme.field, border: Theme.fieldBorder, radius: 10)
    }
}

/** Chips that wrap onto the next line. */
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += row + spacing
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
