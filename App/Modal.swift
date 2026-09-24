import SwiftUI

private struct DismissModalKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /** Closes the modal window the view is in. */
    var dismissModal: () -> Void {
        get { self[DismissModalKey.self] }
        set { self[DismissModalKey.self] = newValue }
    }
}

/** Modal windows and toasts over the whole app, as the Android app's Dialog and Toast. */
@MainActor
final class Overlay: ObservableObject {
    struct Window: Identifiable {
        let id = UUID()
        let width: CGFloat
        let content: AnyView
        let onDismiss: (() -> Void)?
    }

    @Published private(set) var windows: [Window] = []
    @Published private(set) var toastText: String?
    private var toastTask: Task<Void, Never>?

    /** A window at most `width` wide (less on a narrow screen), dimmed background, closes on a tap outside. */
    @discardableResult
    func show<V: View>(width: CGFloat, onDismiss: (() -> Void)? = nil, @ViewBuilder _ content: () -> V) -> UUID {
        let window = Window(width: width, content: AnyView(content()), onDismiss: onDismiss)
        windows.append(window)
        return window.id
    }

    func dismiss(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let window = windows.remove(at: index)
        window.onDismiss?()
    }

    func toast(_ text: String) {
        toastText = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { toastText = nil }
        }
    }
}

struct OverlayHost: View {
    @ObservedObject var overlay: Overlay

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(overlay.windows) { window in
                    ZStack {
                        Color.black.opacity(0.65)
                            .ignoresSafeArea()
                            .onTapGesture { overlay.dismiss(window.id) }
                        window.content
                            .frame(width: min(window.width, geo.size.width - 32))
                            .frame(maxHeight: geo.size.height - 24)
                            .environment(\.dismissModal, { overlay.dismiss(window.id) })
                    }
                    .transition(.opacity)
                }
                if let text = overlay.toastText {
                    VStack {
                        Spacer()
                        Text(text)
                            .font(Theme.medium(13))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .box(Color(hex: 0x2A2B30), radius: 20, border: Theme.panelBorder)
                            .padding(.bottom, 24)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeOut(duration: 0.15), value: overlay.windows.map(\.id))
        .animation(.easeOut(duration: 0.2), value: overlay.toastText)
    }
}

/** The launcher's modal window: dark card, title with a close cross, scrolling body, button row. */
struct ModalCard<Content: View, Footer: View>: View {
    @Environment(\.dismissModal) private var dismiss
    let title: String
    let content: Content
    let footer: Footer

    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.bold(18))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                IconButton(icon: "ic_close", color: Theme.text2, size: 20, box: 32) { dismiss() }
            }
            // Wraps its content, scrolls when the window would be taller than the screen
            ViewThatFits(in: .vertical) {
                bodyStack
                ScrollView { bodyStack }.scrollIndicators(.hidden)
            }
            .padding(.top, 12)
            if Footer.self != EmptyView.self {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    footer
                }
                .frame(height: 40)
                .padding(.top, 16)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))
        .box(Theme.panel, radius: 16, border: Theme.panelBorder)
    }

    private var bodyStack: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ModalCard where Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, content: content, footer: { EmptyView() })
    }
}

/** Body text of a window (Modal.text). */
struct ModalText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.regular(13))
            .foregroundStyle(Theme.text2)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
    }
}

/** Label on the left, value on the right: the rows of the memory and disk space windows. */
struct ModalPair: View {
    let label: String
    let value: String
    var color = Theme.text

    var body: some View {
        HStack {
            Text(label).font(Theme.medium(13)).foregroundStyle(Theme.text2)
            Spacer()
            Text(value).font(Theme.semibold(13)).foregroundStyle(color)
        }
        .padding(.vertical, 6)
    }
}

/** Footer button that closes its window, then runs the action (unless `closes` is false). */
struct ModalPrimary: View {
    @Environment(\.dismissModal) private var dismiss
    let label: String
    var closes = true
    var action: () -> Void = {}

    var body: some View {
        PrimaryButton(label: label) {
            if closes { dismiss() }
            action()
        }
    }
}

struct ModalSecondary: View {
    @Environment(\.dismissModal) private var dismiss
    let label: String
    var closes = true
    var action: () -> Void = {}

    var body: some View {
        SecondaryButton(label: label) {
            if closes { dismiss() }
            action()
        }
    }
}

/** Monospace log text in a field box, selectable. */
struct LogText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Theme.chipText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .box(Theme.field, radius: 8, border: Theme.fieldBorder)
    }
}
