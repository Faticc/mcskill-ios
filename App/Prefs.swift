import Foundation

/** Launcher state that survives restarts (LauncherPrefs of the Android app). */
enum Prefs {
    private static let store = UserDefaults.standard

    static var lastClientId: Int {
        get { store.integer(forKey: "lastClientId") }
        set { store.set(newValue, forKey: "lastClientId") }
    }

    static var favourites: Set<Int> {
        get { Set((store.array(forKey: "favourites") as? [Int]) ?? []) }
        set { store.set(Array(newValue), forKey: "favourites") }
    }

    static var memoryAuto: Bool {
        get { store.object(forKey: "memoryAuto") as? Bool ?? true }
        set { store.set(newValue, forKey: "memoryAuto") }
    }

    /** "Фоновое свечение". */
    static var glow: Bool {
        get { store.object(forKey: "glow") as? Bool ?? true }
        set { store.set(newValue, forKey: "glow") }
    }

    /** "Режим отладки". */
    static var debug: Bool {
        get { store.bool(forKey: "debug") }
        set { store.set(newValue, forKey: "debug") }
    }

    /** "Запомнить меня" off: the session is dropped on the next start. */
    static var forgetAccount: Bool {
        get { store.bool(forKey: "forgetAccount") }
        set { store.set(newValue, forKey: "forgetAccount") }
    }

    /** "Проверить все файлы при следующем запуске". */
    static func fullCheck(_ clientId: Int) -> Bool {
        store.bool(forKey: "fullCheck:id:\(clientId)")
    }

    static func setFullCheck(_ clientId: Int, _ on: Bool) {
        store.set(on, forKey: "fullCheck:id:\(clientId)")
    }
}

/** How the game gets desktop OpenGL; the iOS counterparts of the Android renderers. */
enum Renderer: String, CaseIterable {
    case gl4es
    case gl4esAngle = "gl4es_angle"
    case mobileglues
    case zink

    var title: String {
        switch self {
        case .gl4es: return "GL4ES — системный GLES"
        case .gl4esAngle: return "GL4ES → ANGLE (Metal)"
        case .mobileglues: return "MobileGlues — системный GLES"
        case .zink: return "Zink (Mesa) → MoltenVK"
        }
    }

    /** Goes through Vulkan (MoltenVK), where the driver choice would apply. */
    var usesVulkan: Bool { self == .gl4esAngle || self == .zink }
}

/** Launch settings of the "Настройки" window (Settings.java). */
struct LaunchSettings: Codable, Equatable {
    var ramMb: Int
    var renderer: String
    var driverId: String
    var scale: Double
    var extraJvmArgs: String
    var turbo: Bool
    var forgeSplash: Bool
    var backgroundFps: Int

    static let scales: [Double] = [1, 0.85, 0.75, 0.6, 0.5]
    /** Choices for the frame cap of the minimized game, 0 = none. */
    static let backgroundFpsChoices = [1, 2, 5, 10, 20, 0]

    static var deviceRamMb: Int {
        Int(ProcessInfo.processInfo.physicalMemory >> 20)
    }

    static var defaults: LaunchSettings {
        let ram = min(4096, deviceRamMb / 2)
        return LaunchSettings(ramMb: max(1024, ram - ram % 256), renderer: Renderer.gl4es.rawValue,
                              driverId: "system", scale: 1, extraJvmArgs: "", turbo: false,
                              forgeSplash: true, backgroundFps: 2)
    }

    static func load() -> LaunchSettings {
        guard let data = UserDefaults.standard.data(forKey: "settings"),
              let settings = try? JSONDecoder().decode(LaunchSettings.self, from: data) else { return defaults }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "settings")
        }
    }
}
