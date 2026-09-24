import SwiftUI

/** A tinted icon of the Android set (Assets.xcassets/Icons, made by scripts/import_android_assets.py). */
struct Icon: View {
    let name: String
    let color: Color
    let size: CGFloat

    init(_ name: String, _ color: Color, _ size: CGFloat) {
        self.name = name
        self.color = color
        self.size = size
    }

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
    }
}

/** Uppercase label with a little tracking: section headers and buttons (Ui.caps). */
struct Caps: View {
    let text: String
    let size: CGFloat
    let color: Color

    var body: some View {
        Text(text.caps)
            .font(Theme.bold(size))
            .tracking(size * 0.04)
            .foregroundStyle(color)
    }
}

/** Touch feedback in place of Android's ripple. */
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/** Icon in a square tap area: the close cross, the gear, the star. */
struct IconButton: View {
    let icon: String
    let color: Color
    let size: CGFloat
    let box: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, color, size)
                .frame(width: box, height: box)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/** Big gradient action button: "ИГРАТЬ", "ВОЙТИ". Takes the height the caller gives it. */
struct PrimaryButton: View {
    let label: String
    /** Stretch to the caller's width instead of wrapping the label. */
    var fill = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Caps(text: label, size: 14, color: Theme.text)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(maxWidth: fill ? .infinity : nil, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentGradient))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PressStyle())
    }
}

/** Dark outlined button: "ЗАКРЫТЬ", "НАСТРОЙКИ". Takes the height the caller gives it. */
struct SecondaryButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Caps(text: label, size: 12, color: Theme.chipText)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .box(Theme.tile, radius: 10, border: Theme.panelBorder)
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PressStyle())
    }
}

/** Teal text button with a tinted background: "Подробнее →". */
struct AccentChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.medium(12))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .box(Color(argb: 0x223DA8B8), radius: 7, border: Color(argb: 0x553DA8B8))
        }
        .buttonStyle(PressStyle())
    }
}

struct Chip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(Theme.medium(12))
            .foregroundStyle(Theme.chipText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .box(Theme.tile, radius: 7, border: Theme.panelBorder)
    }
}

/** Chips where one is selected (the settings choices). */
struct Choices: View {
    let labels: [String]
    let selected: Int
    let onChange: (Int) -> Void

    var body: some View {
        FlowLayout(hGap: 6, vGap: 6) {
            ForEach(labels.indices, id: \.self) { i in
                let on = i == selected
                Button { onChange(i) } label: {
                    Text(labels[i])
                        .font(Theme.medium(12))
                        .foregroundStyle(on ? Theme.text : Theme.chipText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .box(on ? Color(argb: 0x333DA8B8) : Theme.tile, radius: 8,
                             border: on ? Theme.accent : Theme.panelBorder)
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

/** A field in a rounded box with a leading icon (Ui.fieldBox). Takes the height the caller gives it. */
struct FieldBox<Trailing: View>: View {
    var icon: String?
    let placeholder: String
    @Binding var text: String
    var secure = false
    var font = Theme.medium(14)
    var alignment = TextAlignment.leading
    var keyboard = UIKeyboardType.default
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let icon { Icon(icon, Theme.text3, 18) }
            Group {
                if secure {
                    SecureField("", text: $text, prompt: prompt)
                } else {
                    TextField("", text: $text, prompt: prompt)
                }
            }
            .font(font)
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(alignment)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .tint(Theme.accent)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
        .box(Theme.field, radius: 10, border: Theme.fieldBorder)
    }

    private var prompt: Text {
        Text(placeholder).foregroundColor(Theme.text3)
    }
}

extension FieldBox where Trailing == EmptyView {
    init(icon: String?, placeholder: String, text: Binding<String>, secure: Bool = false,
         font: Font = Theme.medium(14), alignment: TextAlignment = .leading, keyboard: UIKeyboardType = .default) {
        self.init(icon: icon, placeholder: placeholder, text: text, secure: secure, font: font,
                  alignment: alignment, keyboard: keyboard, trailing: { EmptyView() })
    }
}

/** Section title with the short teal underline of the launcher's cards. */
struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.semibold(14))
                .foregroundStyle(Theme.text)
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.accent)
                .frame(width: 40, height: 2)
        }
    }
}

/** On/off switch in the launcher's colors (Toggle.java): 40x22, the knob slides in 150 ms. */
struct Switch: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(isOn ? Theme.accent : Theme.tile)
            Circle()
                .fill(isOn ? Color.white : Theme.text2)
                .frame(width: 16, height: 16)
                .offset(x: isOn ? 21 : 3)
        }
        .frame(width: 40, height: 22)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        }
    }
}

/** Thin rounded progress bar with the teal gradient; nil shows a sliding segment. */
struct ProgressLine: View {
    let value: Double?

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.tile)
                if let value {
                    if value > 0 {
                        Capsule().fill(Theme.accentGradient).frame(width: max(h, w * min(1, value)))
                    }
                } else {
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        let segment = w * 0.3
                        let x = -segment + (w + segment) * t
                        let start = max(0, x), end = min(w, x + segment)
                        Capsule().fill(Theme.accentGradient)
                            .frame(width: max(0, end - start))
                            .offset(x: start)
                    }
                }
            }
        }
    }
}

/** Children left to right, wrapping to new lines: the mod chips. */
struct FlowLayout: Layout {
    var hGap: CGFloat = 6
    var vGap: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += line + vGap
                line = 0
            }
            x += size.width + hGap
            widest = max(widest, x - hGap)
            line = max(line, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > 0 && x + size.width > bounds.width {
                x = 0
                y += line + vGap
                line = 0
            }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + hGap
            line = max(line, size.height)
        }
    }
}
