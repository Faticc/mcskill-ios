import HTSCore
import SwiftUI

/** Home: the account's servers (main / test), pull to refresh, a server's page on tap. */
struct ServersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var testTab = false

    private var hasTest: Bool { model.servers.contains { $0.isTest } }

    private var visible: [ServerInfo] {
        model.servers
            .filter { $0.isTest == (testTab && hasTest) }
            .sorted { $0.online > $1.online }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    header
                    if hasTest {
                        Picker("", selection: $testTab) {
                            Text("Основные").tag(false)
                            Text("Тестовые").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    if let error = model.serversError {
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .card(fill: Theme.tileRed, border: Theme.red.opacity(0.4), radius: 10)
                    }
                    if visible.isEmpty {
                        Text(model.loadingServers ? "Загрузка серверов…" : "Серверов нет")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text3)
                            .padding(.top, 40)
                    }
                    ForEach(visible) { server in
                        NavigationLink(value: server) {
                            ServerRow(server: server)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await model.refreshServers() }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ServerInfo.self) { ServerDetailView(server: $0) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(String(model.session?.profile.username.prefix(1) ?? "?").uppercased())
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .card(fill: Theme.tileTeal, border: Theme.accent.opacity(0.4), radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.session?.profile.username ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("McSkill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text2)
            }
            Spacer()
            Menu {
                ShareLink("Поделиться логами", item: AppLog.fileURL)
                Button("Выйти", role: .destructive) { model.signOut() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 42, height: 42)
                    .card(radius: 10)
            }
        }
        .padding(.vertical, 8)
    }
}

struct ServerRow: View {
    let server: ServerInfo

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(server.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    TagChip(tag: server.tag)
                }
                HStack(spacing: 6) {
                    Text(server.version)
                    Text("·")
                    Circle()
                        .fill(server.tag == .maintenance ? Theme.red : Theme.green)
                        .frame(width: 7, height: 7)
                    Text("\(server.online)")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text3)
        }
        .padding(14)
        .card()
        .contentShape(Rectangle())
    }
}

/** "● ВАЙП" / "● НОВЫЙ" / "● ТЕХ. РАБОТЫ" next to a server's name. */
struct TagChip: View {
    let tag: ServerInfo.Tag

    var body: some View {
        if let style {
            HStack(spacing: 4) {
                Circle().fill(style.color).frame(width: 5, height: 5)
                Text(style.label.uppercased())
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(style.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(style.color.opacity(0.15)))
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

struct ServerDetailView: View {
    let server: ServerInfo

    private var mode: String {
        switch server.mode {
        case .pvp: return "PVP"
        case .pve: return "PVE"
        case .unknown: return "—"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Text(server.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.text)
                    TagChip(tag: server.tag)
                }
                if !server.description.isEmpty {
                    section("Описание сервера") {
                        Text(server.description)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text2)
                    }
                }
                section("Информация о сервере") {
                    HStack(spacing: 10) {
                        InfoTile(icon: "shippingbox", color: Theme.accent, fill: Theme.tileTeal,
                                 value: server.version, label: "Версия")
                        InfoTile(icon: "shield", color: server.mode == .pvp ? Theme.red : Theme.accent,
                                 fill: server.mode == .pvp ? Theme.tileRed : Theme.tileTeal,
                                 value: mode, label: "Режим игры")
                        InfoTile(icon: "calendar", color: Theme.green, fill: Theme.tileGreen,
                                 value: Format.wipeDate(server.wipeDate), label: "Дата вайпа")
                    }
                }
                if !server.mods.isEmpty {
                    section("Модификации · \(Format.mods(server.mods.count))") {
                        FlowLayout(spacing: 6) {
                            ForEach(server.mods.sorted { $0.name.lowercased() < $1.name.lowercased() }, id: \.self) { mod in
                                Text(mod.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.chipText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .card(fill: Theme.tile, radius: 6)
                            }
                        }
                    }
                }
                VStack(spacing: 8) {
                    Button("Играть") {}
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(true)
                        .opacity(0.4)
                    Text("Запуск игры на iOS ещё в разработке")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text3)
                }
            }
            .padding(16)
        }
        .background(AppBackground())
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Theme.text3)
            content()
        }
    }
}

struct InfoTile: View {
    let icon: String
    let color: Color
    let fill: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .card(radius: 10)
    }
}
