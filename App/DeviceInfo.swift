import HTSCore
import UIKit

enum DeviceInfo {
    /** Hardware id like "iPhone16,1", which tells the chip (and so the JIT method) apart. */
    static var machine: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    @MainActor
    static var summary: String {
        let bundle = Bundle.main.infoDictionary
        let version = bundle?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        return "HTS \(version) (\(build)), \(machine), \(device.systemName) \(device.systemVersion)"
    }
}

/** Data for `--demo` launches (simulator screenshots). */
enum Demo {
    static let session = McSkillSession(
        id: "demo",
        profile: McSkillProfile(uuid: "00000000-0000-0000-0000-000000000000", username: "Faticc", skinURL: "")
    )

    private static let hitechMods: [ServerInfo.Mod] = [
        .init(name: "IndustrialCraft 2", tags: ["main"]), .init(name: "GregTech", tags: ["main"]),
        .init(name: "Applied Energistics 2", tags: ["main"]), .init(name: "BuildCraft"),
        .init(name: "Thermal Expansion"), .init(name: "NotEnoughItems"), .init(name: "OptiFine"),
        .init(name: "Forestry"), .init(name: "Railcraft"), .init(name: "Galacticraft"),
        .init(name: "Advanced Solar Panels", tags: ["custom"]), .init(name: "Draconic Evolution"),
        .init(name: "Ender IO"), .init(name: "Mekanism"), .init(name: "Iron Chests"),
        .init(name: "Journey Map"), .init(name: "Nuclear Control", tags: ["custom"]),
    ]

    static let servers: [ServerInfo] = [
        ServerInfo(id: 89, title: "HiTech", version: "1.7.10",
                   description: "Индустриальная сборка: заводы, реакторы, космос. Развивайтесь от первых механизмов до квантовой брони и полётов на другие планеты.",
                   aboutURL: "https://mcskill.net/", online: 214, mode: .pve, wipeDate: "1756684800", tag: .wipe,
                   mods: hitechMods),
        ServerInfo(id: 90, title: "Oneblock", version: "1.20.1", online: 97, mode: .pve, tag: .new),
        ServerInfo(id: 91, title: "FrozenTech", version: "1.21.1", online: 58, mode: .pvp),
        ServerInfo(id: 92, title: "Magic", version: "1.7.10", online: 0, mode: .pvp, tag: .maintenance),
        ServerInfo(id: 94, title: "Divine RPG", version: "1.7.10", online: 31, mode: .pvp),
        ServerInfo(id: 95, title: "Sky Factory", version: "1.12.2", online: 12, mode: .pve),
        ServerInfo(id: 93, title: "Test HiTech", version: "1.7.10", online: 3, isTest: true),
    ]

    static let runtimes: [JavaRuntime] = [(8, "1.8.0_472"), (17, "17.0.20"), (25, "25.0.4")].map {
        JavaRuntime(major: $0.0, version: $0.1,
                    home: JavaRuntimes.root.appendingPathComponent("java-\($0.0)-openjdk", isDirectory: true))
    }

    static let jit = JITStatus(enabled: false, debugger: false, flags: [.iOS26, .txm])

    static func probe(_ runtime: JavaRuntime) -> JavaProbeResult {
        JavaProbeResult(runtime: runtime,
                        properties: ["java.version": runtime.version, "java.vm.name": "OpenJDK 64-Bit Server VM",
                                     "java.vm.info": "mixed mode"],
                        startMs: 412, sortMs: [2140, 388, 96, 91, 90, 92],
                        compiler: "HotSpot 64-Bit Tiered Compilers", compileMs: 1830, processors: 6, maxMemoryMb: 256)
    }

    static func profile(_ server: ServerInfo) -> ClientProfileInfo {
        ClientProfileInfo(id: server.id, version: server.version, clientDir: server.title, javaVersion: "25-temurin",
                          minimumRam: 3072, recommendedRam: 4096)
    }
}
