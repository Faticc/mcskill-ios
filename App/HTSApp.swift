import HTSCore
import SwiftUI

@main
struct HTSApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            AppBackground()
            if model.session == nil {
                LoginView()
            } else {
                ServersView()
            }
        }
    }
}

/** Who is signed in and which servers they see; the screens only draw this. */
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: McSkillSession?
    @Published private(set) var servers: [ServerInfo] = []
    @Published private(set) var loadingServers = false
    @Published private(set) var serversError: String?

    /** `--demo`: fake account and servers, for simulator screenshots without an account. */
    let demo = ProcessInfo.processInfo.arguments.contains("--demo")

    init() {
        AppLog.info("Start \(DeviceInfo.summary)\(demo ? " (demo)" : "")")
        if demo {
            session = Demo.session
            servers = Demo.servers
            return
        }
        session = SessionStore.load()
        servers = ServerCache.load()
        if session != nil {
            Task { await refreshServers() }
        }
    }

    func signedIn(_ session: McSkillSession) {
        AppLog.info("Signed in as \(session.profile.username)")
        SessionStore.save(session)
        self.session = session
        Task { await refreshServers() }
    }

    func refreshServers() async {
        guard let session, !demo else { return }
        loadingServers = true
        defer { loadingServers = false }
        do {
            let list = try await McSkillAPI.shared.servers(session: session.id)
            AppLog.info("Servers: \(list.count)")
            servers = list
            serversError = nil
            ServerCache.save(list)
        } catch {
            let e = McSkillError.from(error)
            AppLog.error("Servers failed: \(e.code) \(e.message ?? "")")
            if e.code == .unauthenticated {
                signOut()
            } else {
                serversError = e.localizedDescription
            }
        }
    }

    func signOut() {
        AppLog.info("Sign out")
        let id = session?.id
        SessionStore.clear()
        ServerCache.clear()
        session = nil
        servers = []
        serversError = nil
        if let id, !demo {
            Task.detached { try? await McSkillAPI.shared.logout(session: id) }
        }
    }
}
