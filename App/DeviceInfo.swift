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

    static var summary: String {
        let bundle = Bundle.main.infoDictionary
        let version = bundle?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        return "HTS \(version) (\(build)), \(machine), \(device.systemName) \(device.systemVersion)"
    }
}

/** Data for `--demo` launches. */
enum Demo {
    static let session = McSkillSession(
        id: "demo",
        profile: McSkillProfile(uuid: "00000000-0000-0000-0000-000000000000", username: "Demo", skinURL: "")
    )

    static let servers: [ServerInfo] = [
        ServerInfo(id: 89, title: "HiTech", version: "1.7.10",
                   description: "Индустриальная сборка: IndustrialCraft 2, GregTech, Applied Energistics и другие.",
                   online: 214, mode: .pve, wipeDate: "1756684800", tag: .wipe,
                   mods: ["IndustrialCraft 2", "Applied Energistics 2", "BuildCraft", "Thermal Expansion",
                          "NotEnoughItems", "OptiFine", "Forestry", "Railcraft"].map { .init(name: $0) }),
        ServerInfo(id: 90, title: "Oneblock", version: "1.20.1", online: 97, mode: .pve, tag: .new),
        ServerInfo(id: 91, title: "FrozenTech", version: "1.21.1", online: 58, mode: .pvp),
        ServerInfo(id: 92, title: "Magic", version: "1.7.10", online: 0, mode: .pvp, tag: .maintenance),
        ServerInfo(id: 93, title: "Test HiTech", version: "1.7.10", online: 3, isTest: true),
    ]
}
