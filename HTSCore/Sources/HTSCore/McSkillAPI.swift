import Foundation
import GRPC
import McSkillProto
import NIOCore

/**
 * The McSkill launcher API (launchernew.mcskill.ru, gRPC over TLS) on one channel for the whole
 * app; the channel connects lazily and reconnects by itself.
 */
public final class McSkillAPI: @unchecked Sendable {
    public static let defaultHost = "launchernew.mcskill.ru"
    public static let shared = McSkillAPI()

    /** Upper bound for one RPC, so a hung server cannot hold a screen forever. */
    private static let deadline = TimeAmount.seconds(30)

    private let group: EventLoopGroup
    private let channel: GRPCChannel
    private let auth: Launcher_AuthServiceAsyncClient
    private let clients: Launcher_ClientServiceAsyncClient

    public init(host: String = McSkillAPI.defaultHost, port: Int = 443) {
        // Network.framework on iOS/macOS
        group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
        // Throws only for an invalid configuration, which this one is not
        channel = try! GRPCChannelPool.with(
            target: .host(host, port: port),
            transportSecurity: .tls(GRPCTLSConfiguration.makeClientDefault(compatibleWith: group)),
            eventLoopGroup: group
        )
        auth = Launcher_AuthServiceAsyncClient(channel: channel)
        clients = Launcher_ClientServiceAsyncClient(channel: channel)
    }

    /** - Parameter totp: code of the authenticator app, or nil */
    public func login(username: String, password: String, totp: String?) async throws -> LoginResult {
        var request = Launcher_LoginRequest()
        request.username = username
        request.password = password
        if let totp, !totp.isEmpty { request.totp = totp }
        let response = try await call { try await auth.login(request, callOptions: options(session: nil)) }
        switch response.result {
        case .sessionData(let s)?:
            return .session(McSkillSession(id: s.id, profile: McSkillProfile(s.profile)))
        case .mfaRequired?:
            return .mfaRequired
        case .totp?:
            return .totpRequired
        case nil:
            throw McSkillError(code: .unknown, message: "Unrecognized login response")
        }
    }

    public func logout(session: String) async throws {
        _ = try await call { try await auth.logout(Launcher_LogoutRequest(), callOptions: options(session: session)) }
    }

    public func profile(session: String) async throws -> McSkillProfile {
        let response = try await call {
            try await auth.getProfile(Launcher_GetProfileRequest(), callOptions: options(session: session))
        }
        return McSkillProfile(response.profile)
    }

    /** The servers the account sees, test ones included (``ServerInfo/isTest``). */
    public func servers(session: String) async throws -> [ServerInfo] {
        let response = try await call {
            try await clients.getClients(Launcher_GetClientsRequest(), callOptions: options(session: session))
        }
        return response.clients.map(ServerInfo.init)
    }

    private func options(session: String?) -> CallOptions {
        var options = CallOptions()
        options.timeLimit = .timeout(Self.deadline)
        if let session { options.customMetadata.add(name: "session", value: session) }
        return options
    }

    private func call<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            throw McSkillError.from(error)
        }
    }
}
