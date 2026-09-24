import Foundation
import Security

/** The signed-in session, in the keychain (survives reinstalls of the same bundle id). */
public enum SessionStore {
    private static let service = "ru.hts.launcher.session"
    private static let account = "current"

    public static func load() -> McSkillSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(McSkillSession.self, from: data)
    }

    public static func save(_ session: McSkillSession) {
        clear()
        guard let data = try? JSONEncoder().encode(session) else { return }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { AppLog.error("Keychain: cannot save the session (\(status))") }
    }

    public static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/** The last server list, so the home screen fills instantly before the API answers. */
public enum ServerCache {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("servers.json")
    }

    public static func load() -> [ServerInfo] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ServerInfo].self, from: data)) ?? []
    }

    public static func save(_ servers: [ServerInfo]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(servers).write(to: url, options: .atomic)
        } catch {
            AppLog.error("Cannot cache the server list: \(error)")
        }
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
