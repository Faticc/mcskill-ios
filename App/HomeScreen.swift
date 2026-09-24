import HTSCore
import SwiftUI

private struct AccountChipKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/**
 * Main screen, laid out like the McSkill launcher: server list on the left (favourites, popular,
 * all), the chosen server on the right, the "your choice / ИГРАТЬ" bar at the bottom.
 */
struct HomeScreen: View {
    private static let modsShown = 12

    @EnvironmentObject private var model: AppModel
    @State private var testTab = false

    var body: some View {
        GeometryReader { geo in
            let listWidth = max(220, min(300, geo.size.width * 0.3))
            VStack(spacing: 0) {
                header
                    .frame(height: 42)
                HStack(alignment: .top, spacing: 14) {
                    ScrollView { serverList }
                        .scrollIndicators(.hidden)
                        .frame(width: listWidth)
                    VStack(spacing: 8) {
                        ScrollView { details }
                            .scrollIndicators(.hidden)
                            .id(model.selectedId)
                            .frame(maxHeight: .infinity)
                        bottomBar
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .overlayPreferenceValue(AccountChipKey.self) { anchor in
            accountMenu(anchor)
        }
        .onAppear {
            if model.selected?.isTest == true { testTab = true }
        }
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 0) {
            Text("McSkill")
                .font(Theme.bold(17))
                .foregroundStyle(Theme.text)
            Spacer()
            Button { model.accountMenuOpen = true } label: {
                HStack(spacing: 0) {
                    SkinHead(username: model.session?.profile.username ?? "",
                             skinURL: model.session?.profile.skinURL ?? "")
                    Text(model.session?.profile.username ?? "")
                        .font(Theme.semibold(14))
                        .foregroundStyle(Theme.text)
                        .padding(.leading, 8)
                        .padding(.trailing, 6)
                    Icon("ic_chevron_down", Theme.text2, 16)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .anchorPreference(key: AccountChipKey.self, value: .bounds) { $0 }
            Rectangle()
                .fill(Theme.panelBorder)
                .frame(width: 1, height: 20)
                .padding(.leading, 8)
                .padding(.trailing, 4)
            IconButton(icon: "ic_settings", color: Theme.text2, size: 20, box: 36) { model.openSettings() }
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
    }

    @ViewBuilder
    private func accountMenu(_ anchor: Anchor<CGRect>?) -> some View {
        if model.accountMenuOpen, let anchor {
            GeometryReader { geo in
                let chip = geo[anchor]
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { model.accountMenuOpen = false }
                    VStack(spacing: 0) {
                        menuItem("ic_user_plus", "Добавить аккаунт", Theme.text3, nil)
                        menuItem("ic_logout", "Выйти", Theme.red) { model.logout() }
                    }
                    .padding(6)
                    .frame(width: 200)
                    .box(Theme.panel, radius: 12, border: Theme.panelBorder)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                    .offset(x: min(chip.minX, geo.size.width - 200), y: chip.maxY + 4)
                }
            }
        }
    }

    @ViewBuilder
    private func menuItem(_ icon: String, _ label: String, _ color: Color, _ action: (() -> Void)?) -> some View {
        let row = HStack(spacing: 0) {
            Icon(icon, color, 16)
            Text(label)
                .font(Theme.medium(13))
                .foregroundStyle(color)
                .padding(.leading, 10)
            Spacer(minLength: 4)
            if action == nil {
                Text("Скоро")
                    .font(Theme.medium(10))
                    .foregroundStyle(Theme.text3)
            }
        }
        .padding(10)
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { row }.buttonStyle(PressStyle())
        } else {
            row.opacity(0.7)
        }
    }

    // MARK: - server list

    private var serverList: some View {
        let hasTests = model.servers.contains { $0.isTest }
        let tab = testTab && hasTests
        let pool = model.servers.filter { $0.isTest == tab }
        let favourites = pool.filter { model.favourites.contains($0.id) }
        var rest = pool.filter { !model.favourites.contains($0.id) }
        let popular = Array(rest.sorted { $0.online > $1.online }.prefix(3))
        rest.removeAll { server in popular.contains { $0.id == server.id } }
        rest.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        return VStack(alignment: .leading, spacing: 0) {
            if hasTests {
                tabs
                    .frame(height: 34)
                    .padding(.bottom, 8)
            }
            if model.servers.isEmpty {
                Text("Загрузка серверов…")
                    .font(Theme.medium(13))
                    .foregroundStyle(Theme.text3)
                    .padding(.leading, 4)
                    .padding(.top, 8)
            } else {
                if !favourites.isEmpty {
                    section("ic_star", "Избранное", Theme.gold, favourites, first: !hasTests)
                }
                if !popular.isEmpty {
                    section("ic_rocket", "Популярное", Theme.text2, popular, first: !hasTests && favourites.isEmpty)
                }
                if !rest.isEmpty {
                    section("ic_server", "Все сервера", Theme.text2, rest,
                            first: !hasTests && favourites.isEmpty && popular.isEmpty)
                }
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { test in
                let on = test == testTab
                Button { testTab = test } label: {
                    Text(test ? "Тестовые" : "Основные")
                        .font(Theme.semibold(12))
                        .foregroundStyle(on ? Theme.text : Theme.text2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.tile : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(3)
        .box(Theme.card, radius: 9, border: Theme.cardBorder)
    }

    private func section(_ icon: String, _ title: String, _ color: Color, _ items: [ServerInfo], first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Icon(icon, color, 13)
                Caps(text: title, size: 11, color: color)
            }
            .padding(.leading, 2)
            .padding(.top, first ? 2 : 8)
            ForEach(items) { serverCard($0) }
        }
        .padding(.bottom, 8)
    }

    private func serverCard(_ server: ServerInfo) -> some View {
        let selected = model.selectedId == server.id
        return Button { model.select(server) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(server.title)
                        .font(Theme.semibold(13.5))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    TagLabel(tag: server.tag)
                }
                HStack(spacing: 0) {
                    Text(server.version)
                    Spacer(minLength: 4)
                    Text("\(server.online)")
                    Circle()
                        .fill(server.tag == .maintenance ? Theme.red : Theme.green)
                        .frame(width: 6, height: 6)
                        .padding(.leading, 6)
                }
                .font(Theme.medium(11))
                .foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .box(Theme.card, radius: 10, border: selected ? Theme.goldBorder : Theme.cardBorder)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    // MARK: - details

    @ViewBuilder
    private var details: some View {
        if let server = model.selected {
            VStack(alignment: .leading, spacing: 0) {
                titleRow(server)
                    .padding(.bottom, 8)
                if !server.description.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Описание сервера")
                        Text(server.description)
                            .font(Theme.regular(12.5))
                            .foregroundStyle(Theme.chipText)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }
                    .panelCard()
                    .padding(.bottom, 12)
                }
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Информация о сервере")
                    HStack(spacing: 10) {
                        InfoTile(icon: "ic_box", color: Theme.accent, iconBg: Theme.tileTeal,
                                 value: server.version, label: "Версия")
                        let pvp = server.mode == .pvp
                        InfoTile(icon: pvp ? "ic_swords" : "ic_shield", color: pvp ? Theme.red : Theme.blue,
                                 iconBg: pvp ? Theme.tileRed : Theme.tileTeal, value: modeName(server.mode),
                                 label: "Режим игры")
                        InfoTile(icon: "ic_calendar", color: Theme.green, iconBg: Theme.tileGreen,
                                 value: Format.wipeDate(server.wipeDate), label: "Дата вайпа")
                    }
                    .padding(.top, 12)
                }
                .panelCard()
                .padding(.bottom, 12)
                if !server.mods.isEmpty {
                    let mods = server.mods.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Модификации")
                        FlowLayout(hGap: 6, vGap: 6) {
                            ForEach(Array(mods.prefix(Self.modsShown).enumerated()), id: \.offset) { _, mod in
                                Chip(label: mod.name)
                            }
                            if mods.count > Self.modsShown {
                                AccentChip(label: "Подробнее →") { model.openMods(server) }
                            }
                        }
                        .padding(.top, 12)
                    }
                    .panelCard()
                    .padding(.bottom, 4)
                }
            }
        } else {
            VStack(spacing: 0) {
                Icon("ic_server", Theme.text3, 36)
                Text("Сервер не выбран")
                    .font(Theme.bold(16))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 12)
                Text("Выберите сервер из списка слева, чтобы увидеть подробную информацию")
                    .font(Theme.regular(12))
                    .foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
    }

    private func titleRow(_ server: ServerInfo) -> some View {
        let fav = model.favourites.contains(server.id)
        return HStack(spacing: 0) {
            Text(server.title)
                .font(Theme.bold(21))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            IconButton(icon: fav ? "ic_star_filled" : "ic_star", color: fav ? Theme.accent : Theme.text3,
                       size: 22, box: 32) { model.toggleFavourite(server.id) }
                .padding(.leading, 6)
            if !server.aboutURL.isEmpty {
                Button { Platform.open(server.aboutURL) } label: {
                    HStack(spacing: 6) {
                        Icon("ic_megaphone", Theme.accent, 13)
                        Text("Последнее обновление")
                            .font(Theme.medium(12))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                        Icon("ic_external", Theme.accent, 12)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .box(Color(argb: 0x1A3DA8B8), radius: 7, border: Color(argb: 0x553DA8B8))
                }
                .buttonStyle(PressStyle())
                .padding(.leading, 8)
            }
            Spacer(minLength: 8)
            IconButton(icon: "ic_help", color: Theme.text2, size: 24, box: 34) { model.openHelp(server) }
        }
    }

    private func modeName(_ mode: ServerInfo.Mode) -> String {
        switch mode {
        case .pvp: return "PVP"
        case .pve: return "PVE"
        case .unknown: return "—"
        }
    }

    // MARK: - bottom bar

    private var bottomBar: some View {
        Group {
            switch model.bar {
            case .idle:
                idleBar
            case let .progress(title, detail, right, fraction, cancellable):
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(Theme.bold(14))
                                .foregroundStyle(Theme.text)
                            Text(detail)
                                .font(Theme.medium(11))
                                .foregroundStyle(Theme.text2)
                        }
                        .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(right)
                            .font(Theme.semibold(12))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .padding(.trailing, 10)
                        if cancellable {
                            SecondaryButton(label: "Отменить") { model.cancel() }
                                .frame(height: 36)
                        }
                    }
                    ProgressLine(value: fraction)
                        .frame(height: 6)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .box(Theme.panel, radius: 12, border: Theme.panelBorder)
    }

    private var idleBar: some View {
        let server = model.selected
        return HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.accentGradient)
                Icon("ic_server", Theme.text, 20)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("Ваш выбор:")
                    .font(Theme.medium(10))
                    .foregroundStyle(Theme.text2)
                Text(server?.title ?? "Сервер не выбран")
                    .font(Theme.bold(15))
                    .foregroundStyle(Theme.text)
                Text(server.map(model.installState) ?? "")
                    .font(Theme.medium(10))
                    .foregroundStyle(Theme.text3)
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
            PrimaryButton(label: "Играть", fill: true) {
                if let server { model.play(server) }
            }
            .frame(width: 140, height: 40)
            .opacity(server == nil ? 0.5 : 1)
        }
    }
}

/** "● ВАЙП" / "● НОВЫЙ" / "● ТЕХ. РАБОТЫ" next to a server's name. */
struct TagLabel: View {
    let tag: ServerInfo.Tag

    var body: some View {
        if let style {
            HStack(spacing: 4) {
                Circle().fill(style.color).frame(width: 5, height: 5)
                Caps(text: style.label, size: 9, color: style.color)
                    .lineLimit(1)
            }
            .fixedSize()
        }
    }

    private var style: (label: String, color: Color)? {
        switch tag {
        case .wipe: return ("Вайп", Theme.wipe)
        case .new: return ("Новый", Theme.green)
        case .maintenance: return ("Тех. работы", Theme.red)
        case .none: return nil
        }
    }
}

struct InfoTile: View {
    let icon: String
    let color: Color
    let iconBg: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(iconBg)
                Icon(icon, color, 17)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(Theme.bold(15))
                    .foregroundStyle(Theme.text)
                Text(label)
                    .font(Theme.medium(11))
                    .foregroundStyle(Theme.text3)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .box(Theme.tile, radius: 10)
    }
}
