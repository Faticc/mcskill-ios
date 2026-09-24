import Foundation
import McSkillProto

/** How to install and start one client (ClientProfile of the API); only what the app reads so far. */
public struct ClientProfileInfo: Sendable, Equatable {
    public var id: Int
    public var version: String
    public var clientDir: String
    public var javaVersion: String
    /** MB; small numbers from the API are GB, see ``megabytes(_:)``. */
    public var minimumRam: Int
    public var recommendedRam: Int

    public init(id: Int, version: String, clientDir: String, javaVersion: String, minimumRam: Int, recommendedRam: Int) {
        self.id = id
        self.version = version
        self.clientDir = clientDir
        self.javaVersion = javaVersion
        self.minimumRam = minimumRam
        self.recommendedRam = recommendedRam
    }

    /** "25-temurin" -> 25, "1.8" -> 8; 0 when unknown. */
    public var javaMajor: Int {
        let numbers = javaVersion.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let first = numbers.first else { return 0 }
        if first == 1, numbers.count > 1 { return numbers[1] }
        return first
    }

    /** Profile memory is MB; small numbers are GB. */
    public static func megabytes(_ value: Int) -> Int {
        value > 0 && value < 128 ? value * 1024 : value
    }
}

extension ClientProfileInfo {
    init(_ p: Launcher_ClientProfile) {
        self.init(id: Int(p.id), version: p.version, clientDir: p.clientDir, javaVersion: p.javaVersion,
                  minimumRam: Int(p.minimumRam), recommendedRam: Int(p.recommendedRam))
    }
}
