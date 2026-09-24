import HTSCore
import SwiftUI

/**
 * The launcher's state and actions (MainActivity of the Android app): who is signed in, the
 * servers, the chosen one, the bottom bar, and the windows the screens open.
 */
@MainActor
final class AppModel: ObservableObject {
    enum Bar: Equatable {
        case idle
        /** Syncing or preparing; a nil fraction is indeterminate. */
        case progress(title: String, detail: String, right: String, fraction: Double?, cancellable: Bool)
    }

    @Published private(set) var session: McSkillSession?
    @Published private(set) var servers: [ServerInfo] = []
    @Published private(set) var selectedId: Int?
    @Published private(set) var bar: Bar = .idle
    @Published private(set) var favourites = Prefs.favourites
    @Published var glow = Prefs.glow
    @Published var accountMenuOpen = false

    let overlay = Overlay()
    private(set) lazy var login = LoginFlow(model: self)

    /** `--demo`: a fake account and servers, for simulator screenshots without an account. */
    let demo: Bool
    /** `--screen <name>` with `--demo`: a window or state to open for the screenshot. */
    private let demoScreen: String?
    private var work: Task<Void, Never>?

    init() {
        let args = ProcessInfo.processInfo.arguments
        demo = args.contains("--demo")
        demoScreen = args.firstIndex(of: "--screen").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        AppLog.info("Start \(DeviceInfo.summary)\(demo ? " (demo \(demoScreen ?? "home"))" : "")")
        if demo {
            if !["login", "mfa", "totp"].contains(demoScreen ?? "") { session = Demo.session }
            servers = Demo.servers
            pickSelection()
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                openDemoScreen()
            }
            return
        }
        if Prefs.forgetAccount { SessionStore.clear() }
        session = SessionStore.load()
        servers = ServerCache.load()
        pickSelection()
        if session != nil {
            Task { await refresh() }
        }
    }

    var selected: ServerInfo? {
        servers.first { $0.id == selectedId }
    }

    func select(_ server: ServerInfo) {
        selectedId = server.id
        Prefs.lastClientId = server.id
    }

    /** Keeps the choice, else the last one, else the first main server. */
    private func pickSelection() {
        if let id = selectedId, servers.contains(where: { $0.id == id }) { return }
        let last = Prefs.lastClientId
        if servers.contains(where: { $0.id == last }) {
            selectedId = last
        } else {
            selectedId = servers.first(where: { !$0.isTest })?.id
        }
    }

    func toggleFavourite(_ id: Int) {
        if favourites.contains(id) { favourites.remove(id) } else { favourites.insert(id) }
        Prefs.favourites = favourites
    }

    /** Installed state line under the chosen server's name; nothing is installed on iOS yet. */
    func installState(_ server: ServerInfo) -> String {
        "Файлы будут загружены при первом запуске"
    }

    // MARK: - account

    func signedIn(_ session: McSkillSession, remember: Bool) {
        AppLog.info("Signed in as \(session.profile.username)")
        Prefs.forgetAccount = !remember
        SessionStore.save(session)
        self.session = session
        pickSelection()
        Task { await refresh() }
    }

    /** Session check and a fresh server list. */
    func refresh() async {
        guard let current = session, !demo else { return }
        do {
            let profile = try await McSkillAPI.shared.profile(session: current.id)
            let list = try await McSkillAPI.shared.servers(session: current.id)
            AppLog.info("Servers: \(list.count)")
            let fresh = McSkillSession(id: current.id, profile: profile)
            if fresh != current { SessionStore.save(fresh) }
            session = fresh
            servers = list
            ServerCache.save(list)
            pickSelection()
        } catch {
            let e = McSkillError.from(error)
            AppLog.error("Refresh failed: \(e.code) \(e.message ?? "")")
            if e.code == .unauthenticated {
                sessionExpired()
            } else {
                overlay.toast(e.localizedDescription)
            }
        }
    }

    private func sessionExpired() {
        SessionStore.clear()
        session = nil
        overlay.toast("Сессия истекла, войдите заново")
    }

    func logout() {
        AppLog.info("Logout")
        accountMenuOpen = false
        let current = session
        SessionStore.clear()
        session = nil
        if let current, !demo {
            Task.detached { try? await McSkillAPI.shared.logout(session: current.id) }
        }
    }

    // MARK: - play

    func play(_ server: ServerInfo) {
        guard bar == .idle else { return }
        if server.tag == .maintenance {
            overlay.show(width: 420) {
                ModalCard("Технические работы") {
                    ModalText("На сервере \(server.title) идут технические работы. Файлы можно обновить, но зайти на сервер, скорее всего, не получится.")
                } footer: {
                    ModalSecondary(label: "Закрыть")
                    ModalPrimary(label: "Продолжить") { self.prepare(server) }
                }
            }
            return
        }
        prepare(server)
    }

    /** Session check and the client's profile, then the Java check. */
    private func prepare(_ server: ServerInfo) {
        guard let current = session else { return }
        bar = .progress(title: "Подготовка к запуску", detail: "Получение данных о клиенте", right: "",
                        fraction: nil, cancellable: false)
        work = Task {
            do {
                let profile: ClientProfileInfo
                if demo {
                    try await Task.sleep(nanoseconds: 600_000_000)
                    profile = Demo.profile(server)
                } else {
                    profile = try await McSkillAPI.shared.clientProfile(id: server.id, session: current.id)
                }
                AppLog.info("Profile \(server.id): java \(profile.javaVersion), dir \(profile.clientDir)")
                bar = .idle
                unavailable(server, profile)
            } catch {
                bar = .idle
                let e = McSkillError.from(error)
                AppLog.error("Profile failed: \(e.code) \(e.message ?? "")")
                if e.code == .unauthenticated {
                    sessionExpired()
                } else {
                    showError("Ошибка подключения", e.localizedDescription) { self.prepare(server) }
                }
            }
        }
    }

    func cancel() {
        work?.cancel()
        bar = .idle
    }

    private func unavailable(_ server: ServerInfo, _ profile: ClientProfileInfo) {
        let java = profile.javaMajor
        overlay.show(width: 440) {
            ModalCard("Клиент недоступен на iOS") {
                ModalText("\(server.title) \(server.version) работает на Java \(java). Встроенной сборки этой Java для iOS пока нет, поэтому клиент не запустится.")
            } footer: {
                ModalPrimary(label: "Закрыть")
            }
        }
    }

    func showError(_ title: String, _ message: String, retry: (() -> Void)? = nil) {
        overlay.show(width: 440) {
            ModalCard(title) {
                ModalText(message)
            } footer: {
                ModalSecondary(label: "Закрыть")
                if let retry { ModalPrimary(label: "Повторить", action: retry) }
            }
        }
    }

    // MARK: - windows

    func openSettings() {
        overlay.show(width: 620) { SettingsModal() }
    }

    func openHelp(_ server: ServerInfo) {
        overlay.show(width: 520) { HelpModal(server: server) }
    }

    func openMods(_ server: ServerInfo) {
        overlay.show(width: 520) { ModsModal(server: server) }
    }

    func showLog() {
        let text = AppLog.tail(maxBytes: 64 * 1024)
        overlay.show(width: 720) {
            ModalCard("Лог игры") {
                LogText(text: text)
            } footer: {
                ModalSecondary(label: "Поделиться", closes: false) { Platform.share(AppLog.fileURL) }
                ModalPrimary(label: "Закрыть")
            }
        }
    }

    func shareLog() {
        Platform.share(AppLog.fileURL)
    }

    func openClientsFolder() {
        if !Platform.openInFiles(Platform.documents.appendingPathComponent("clients", isDirectory: true)) {
            overlay.toast("Не удалось открыть «Файлы»")
        }
    }

    private func openDemoScreen() {
        switch demoScreen {
        case "mfa": login.showMfaDemo()
        case "totp": login.showTotpDemo()
        case "menu": accountMenuOpen = true
        case "settings": openSettings()
        case "progress":
            bar = .progress(title: "Обновление файлов", detail: "Загружено 120.4 МБ из 402.0 МБ · 812 / 2410 файлов",
                            right: "8.2 МБ/с · осталось 34с", fraction: 0.3, cancellable: true)
        default:
            guard let server = selected else { return }
            switch demoScreen {
            case "help": openHelp(server)
            case "mods": openMods(server)
            case "unavailable": unavailable(server, Demo.profile(server))
            default: break
            }
        }
    }
}

/** The login and its 2FA windows (Telegram confirmation, authenticator code). */
@MainActor
final class LoginFlow: ObservableObject {
    @Published var busy = false
    @Published var error: String?
    @Published var mfaNotConfirmed = false
    @Published var totpError: String?

    private unowned let model: AppModel
    private var mfaWindow: UUID?
    private var totpWindow: UUID?

    init(model: AppModel) {
        self.model = model
    }

    /** One login call; a confirmation window that is open gets the outcome. */
    func submit(username: String, password: String, remember: Bool, totp: String? = nil) {
        guard !busy else { return }
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !password.isEmpty else {
            error = "Введите никнейм и пароль"
            return
        }
        error = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                switch try await McSkillAPI.shared.login(username: name, password: password, totp: totp) {
                case .session(let session):
                    closeWindows()
                    model.signedIn(session, remember: remember)
                case .mfaRequired:
                    if mfaWindow != nil {
                        mfaNotConfirmed = true
                    } else {
                        showMfa { self.submit(username: name, password: password, remember: remember) }
                    }
                case .totpRequired:
                    if totpWindow != nil {
                        totpError = "Неверный код. Попробуйте ещё раз"
                    } else {
                        showTotp { code in
                            self.submit(username: name, password: password, remember: remember, totp: code)
                        }
                    }
                }
            } catch {
                let e = McSkillError.from(error)
                AppLog.error("Login failed: \(e.code) \(e.message ?? "")")
                if totpWindow != nil {
                    totpError = e.localizedDescription
                } else {
                    if let id = mfaWindow { model.overlay.dismiss(id) }
                    self.error = e.localizedDescription
                }
            }
        }
    }

    private func showMfa(retry: @escaping () -> Void) {
        mfaNotConfirmed = false
        mfaWindow = model.overlay.show(width: 400, onDismiss: { [weak self] in self?.mfaWindow = nil }) {
            MfaModal(flow: self, retry: retry)
        }
    }

    private func showTotp(submit: @escaping (String) -> Void) {
        totpError = nil
        totpWindow = model.overlay.show(width: 400, onDismiss: { [weak self] in self?.totpWindow = nil }) {
            TotpModal(flow: self, submit: submit)
        }
    }

    private func closeWindows() {
        if let id = mfaWindow { model.overlay.dismiss(id) }
        if let id = totpWindow { model.overlay.dismiss(id) }
    }

    func showMfaDemo() {
        showMfa {}
    }

    func showTotpDemo() {
        showTotp { _ in }
    }
}
