import Foundation
import McSkillProto

/** How to install and start one client (ClientProfile of the API). */
public struct ClientProfileInfo: Sendable, Equatable, Codable {
    public var id: Int
    public var version: String
    public var clientDir: String
    public var javaVersion: String
    /** MB; small numbers from the API are GB, see ``megabytes(_:)``. */
    public var minimumRam: Int
    public var recommendedRam: Int
    public var assetsDir: String
    public var assetIndex: String
    public var mainClass: String
    public var classPath: [String]
    public var jvmArgs: [String]
    public var clientArgs: [String]
    /** INTEGRITY_MODE_BYPASS: existing client files are never compared or deleted. */
    public var integrityBypass: Bool
    /** The files the sync manages: under one of these and none of the exclusions. */
    public var updatePaths: [String]
    public var verifyPaths: [String]
    public var exclusionPaths: [String]

    public init(id: Int, version: String, clientDir: String, javaVersion: String, minimumRam: Int, recommendedRam: Int,
                assetsDir: String = "", assetIndex: String = "", mainClass: String = "", classPath: [String] = [],
                jvmArgs: [String] = [], clientArgs: [String] = [], integrityBypass: Bool = false,
                updatePaths: [String] = [], verifyPaths: [String] = [], exclusionPaths: [String] = []) {
        self.id = id
        self.version = version
        self.clientDir = clientDir
        self.javaVersion = javaVersion
        self.minimumRam = minimumRam
        self.recommendedRam = recommendedRam
        self.assetsDir = assetsDir
        self.assetIndex = assetIndex
        self.mainClass = mainClass
        self.classPath = classPath
        self.jvmArgs = jvmArgs
        self.clientArgs = clientArgs
        self.integrityBypass = integrityBypass
        self.updatePaths = updatePaths
        self.verifyPaths = verifyPaths
        self.exclusionPaths = exclusionPaths
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
                  minimumRam: Int(p.minimumRam), recommendedRam: Int(p.recommendedRam),
                  assetsDir: p.assetsDir, assetIndex: p.assetIndex, mainClass: p.mainClass,
                  classPath: p.classPath, jvmArgs: p.jvmArgs, clientArgs: p.clientArgs,
                  integrityBypass: p.integrityMode == .bypass,
                  updatePaths: p.updatePaths, verifyPaths: p.verifyPaths, exclusionPaths: p.exclusionPaths)
    }
}
