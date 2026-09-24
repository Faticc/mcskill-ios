import Foundation
import McSkillProto

public struct McSkillProfile: Codable, Hashable, Sendable {
    public var uuid: String
    public var username: String
    public var skinURL: String

    public init(uuid: String, username: String, skinURL: String) {
        self.uuid = uuid
        self.username = username
        self.skinURL = skinURL
    }
}

public struct McSkillSession: Codable, Hashable, Sendable {
    public var id: String
    public var profile: McSkillProfile

    public init(id: String, profile: McSkillProfile) {
        self.id = id
        self.profile = profile
    }
}

public enum LoginResult: Sendable {
    case session(McSkillSession)
    /** The login waits for a confirmation sent to the account (Telegram): log in again after it. */
    case mfaRequired
    /** The account uses an authenticator app: log in again with its code. */
    case totpRequired
}

/** One server of the list (ClientInfo of the API), kept apart from the generated types. */
public struct ServerInfo: Codable, Hashable, Identifiable, Sendable {
    public enum Tag: String, Codable, Sendable {
        case none, wipe, new, maintenance
    }

    public enum Mode: String, Codable, Sendable {
        case unknown, pvp, pve
    }

    public struct Mod: Codable, Hashable, Sendable {
        public var name: String
        public var tags: [String]
        public var sort: Int

        public init(name: String, tags: [String] = [], sort: Int = 0) {
            self.name = name
            self.tags = tags
            self.sort = sort
        }
    }

    public var id: Int
    public var title: String
    public var version: String
    public var description: String
    public var aboutURL: String
    public var online: Int
    public var mode: Mode
    /** Epoch seconds as text, see ``Format/wipeDate(_:)``. */
    public var wipeDate: String
    public var tag: Tag
    public var isTest: Bool
    public var mods: [Mod]

    public init(id: Int, title: String, version: String, description: String = "", aboutURL: String = "",
                online: Int = 0, mode: Mode = .unknown, wipeDate: String = "", tag: Tag = .none,
                isTest: Bool = false, mods: [Mod] = []) {
        self.id = id
        self.title = title
        self.version = version
        self.description = description
        self.aboutURL = aboutURL
        self.online = online
        self.mode = mode
        self.wipeDate = wipeDate
        self.tag = tag
        self.isTest = isTest
        self.mods = mods
    }
}

extension McSkillProfile {
    init(_ p: Launcher_PlayerProfile) {
        self.init(uuid: p.uuid, username: p.username, skinURL: p.skinURL)
    }
}

extension ServerInfo {
    init(_ c: Launcher_ClientInfo) {
        let tag: Tag
        switch c.tag {
        case .wipe: tag = .wipe
        case .new: tag = .new
        case .maintenance: tag = .maintenance
        default: tag = .none
        }
        let mode: Mode
        switch c.fightMode {
        case .pvp: mode = .pvp
        case .pve: mode = .pve
        default: mode = .unknown
        }
        self.init(id: Int(c.id), title: c.title, version: c.version, description: c.description_p,
                  aboutURL: c.aboutURL, online: Int(c.online), mode: mode, wipeDate: c.wipeDate,
                  tag: tag, isTest: c.isTest,
                  mods: c.mods.map { Mod(name: $0.name, tags: $0.tags, sort: Int($0.sort)) })
    }
}
