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
    private let updates: Launcher_UpdateServiceAsyncClient

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
        updates = Launcher_UpdateServiceAsyncClient(channel: channel)
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

    /** How to install and start one client: folders, Java, memory. */
    public func clientProfile(id: Int, session: String) async throws -> ClientProfileInfo {
        var request = Launcher_GetClientRequest()
        request.clientID = Int32(id)
        let response = try await call {
            try await clients.getClient(request, callOptions: options(session: session))
        }
        return ClientProfileInfo(response.client)
    }

    // MARK: - update service

    /** Manifest of a client's folder, with the CDN node its files come from. */
    public func fileTree(clientId: Int, session: String) async throws -> FileTree {
        var request = Launcher_FileTreeRequest()
        request.clientID = Int32(clientId)
        let response = try await call {
            try await updates.getFileTree(request, callOptions: options(session: session))
        }
        return FileTree(response)
    }

    /** Manifest of an assets folder (assets_dir of the profile). */
    public func assetFileTree(assetDir: String, session: String) async throws -> FileTree {
        var request = Launcher_AssetFileTreeRequest()
        request.assetDir = assetDir
        let response = try await call {
            try await updates.getAssetFileTree(request, callOptions: options(session: session))
        }
        return FileTree(response)
    }

    /** Another CDN node for a client (or, with assetDir, an assets folder); nil when there is none. */
    public func fallbackNode(clientId: Int?, assetDir: String?, excluding excluded: Set<String>,
                             session: String) async throws -> (baseURL: String, nodeId: String)? {
        var request = Launcher_GetFallbackNodeRequest()
        request.excludedNodeIds = Array(excluded)
        if let clientId {
            var target = Launcher_FallbackClient()
            target.clientID = Int32(clientId)
            request.client = target
        } else {
            var target = Launcher_FallbackAsset()
            target.assetDir = assetDir ?? ""
            request.asset = target
        }
        let response = try await call {
            try await updates.getFallbackNode(request, callOptions: options(session: session))
        }
        return response.baseURL.isEmpty ? nil : (response.baseURL, response.nodeID)
    }

    /**
     * Files as a gRPC stream of chunks (the fallback when no CDN node serves them). A client's
     * files by clientId, an assets folder's by assetDir.
     */
    public func downloadFiles(clientId: Int?, assetDir: String?, paths: [String],
                              session: String) -> AsyncThrowingStream<FileChunk, Error> {
        var callOptions = options(session: session)
        callOptions.timeLimit = .timeout(.minutes(10))
        let stream: GRPCAsyncResponseStream<Launcher_FileChunk>
        if let clientId {
            var request = Launcher_DownloadRequest()
            request.clientID = Int32(clientId)
            request.paths = paths
            stream = updates.downloadFiles(request, callOptions: callOptions)
        } else {
            var request = Launcher_AssetDownloadRequest()
            request.assetDir = assetDir ?? ""
            request.paths = paths
            stream = updates.downloadAssetFiles(request, callOptions: callOptions)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in stream {
                        continuation.yield(FileChunk(path: chunk.path, data: chunk.data, isLast: chunk.isLast))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: McSkillError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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

/** A manifest of the update service: files with BLAKE3 hashes, and where to download them. */
public struct FileTree: Sendable {
    public struct Node: Sendable {
        public var path: String
        public var size: Int64
        /** Lowercase hex BLAKE3; empty when the server sent none. */
        public var hash: String
        public var isDirectory: Bool
    }

    public var files: [Node]
    public var nodeId: String?
    /** CDN base: a file is at base/hh/hash. Empty (assets) means gRPC only. */
    public var baseURL: String?

    public init(files: [Node], nodeId: String? = nil, baseURL: String? = nil) {
        self.files = files
        self.nodeId = nodeId
        self.baseURL = baseURL
    }

    init(_ r: Launcher_FileTreeResponse) {
        files = r.files.map { Node(path: $0.path, size: $0.size, hash: Blake3.hex($0.hash), isDirectory: $0.isDirectory) }
        nodeId = r.hasNodeID ? r.nodeID : nil
        baseURL = r.hasBaseURL ? r.baseURL : nil
    }
}

public struct FileChunk: Sendable {
    public var path: String
    public var data: Data
    public var isLast: Bool
}
