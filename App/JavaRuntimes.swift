import Foundation
import HTSCore

/** A JRE inside HTS.app/java_runtimes: CI puts Amethyst's iOS builds of Java 8, 17 and 25 there. */
struct JavaRuntime: Identifiable, Hashable {
    let major: Int
    /** JAVA_VERSION from the runtime's `release` file, like "17.0.20". */
    let version: String
    let home: URL

    var id: Int { major }
    var title: String { "Java \(major)" }
}

enum JavaRuntimes {
    static let root = Bundle.main.bundleURL.appendingPathComponent("java_runtimes", isDirectory: true)

    /** `java-<major>-openjdk` folders with a readable `release` file, oldest first. */
    static let bundled: [JavaRuntime] = {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap { name -> JavaRuntime? in
            let parts = name.split(separator: "-")
            guard parts.count == 3, parts[0] == "java", let major = Int(parts[1]) else { return nil }
            let home = root.appendingPathComponent(name, isDirectory: true)
            guard let release = try? String(contentsOf: home.appendingPathComponent("release"), encoding: .utf8) else {
                return nil
            }
            return JavaRuntime(major: major, version: releaseValue(release, "JAVA_VERSION") ?? "?", home: home)
        }
        .sorted { $0.major < $1.major }
    }()

    static func releaseValue(_ release: String, _ key: String) -> String? {
        for line in release.split(whereSeparator: \.isNewline) where line.hasPrefix(key + "=") {
            return line.dropFirst(key.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    /**
     * The runtime for a client that asks for Java `major`: 8 only for 8 (old Forge needs exactly
     * that), otherwise the oldest newer one, e.g. 21 → 25.
     */
    static func pick(for major: Int, in runtimes: [JavaRuntime]) -> JavaRuntime? {
        if major <= 8 { return runtimes.first { $0.major == 8 } }
        return runtimes.first { $0.major >= major && $0.major > 8 }
    }

    static let logURL = AppLog.fileURL.deletingLastPathComponent().appendingPathComponent("jvm.log")

    /** Written before a probe, removed after it: still there on start means the JVM took the app down. */
    static let probeMarker = AppLog.fileURL.deletingLastPathComponent().appendingPathComponent("jvm-probe.running")

    /** logs/jvm-probe.json: the last probe's outcome, for CI and for sharing. */
    static let probeReport = AppLog.fileURL.deletingLastPathComponent().appendingPathComponent("jvm-probe.json")

    static func writeProbeReport(_ report: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: probeReport, options: .atomic)
    }

    /** Documents/JIT/UniversalJIT26.js, to be picked in StikDebug's "Assign Script". */
    static let jitScriptFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("JIT", isDirectory: true)

    static func exportJITScript() {
        guard let source = Bundle.main.url(forResource: "UniversalJIT26", withExtension: "js") else { return }
        let fm = FileManager.default
        let target = jitScriptFolder.appendingPathComponent("UniversalJIT26.js")
        try? fm.createDirectory(at: jitScriptFolder, withIntermediateDirectories: true)
        if let old = try? Data(contentsOf: target), let new = try? Data(contentsOf: source), old == new { return }
        try? fm.removeItem(at: target)
        try? fm.copyItem(at: source, to: target)
    }

    static func logTail(maxBytes: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/** How JIT stands on this device right now. */
struct JITStatus {
    let enabled: Bool
    let debugger: Bool
    let flags: HTSJITFlags

    static var current: JITStatus {
        JITStatus(enabled: HTSJava.jitEnabled, debugger: HTSJava.debuggerAttached, flags: HTSJava.jitFlags)
    }

    var title: String { enabled ? "JIT включён" : "JIT выключен" }

    var details: String {
        var parts: [String] = []
        if flags.contains(.iOS26) { parts.append("iOS 26+") }
        if flags.contains(.txm) { parts.append("TXM") }
        if flags.contains(.forceMirrored) { parts.append("зеркальный JIT") }
        if debugger { parts.append("отладчик подключён") }
        return parts.joined(separator: " · ")
    }

    var hint: String {
        if enabled { return "Java может работать. JIT действует до закрытия приложения." }
        if flags.contains(.txm) {
            return "На этом iPhone JIT даёт только StikDebug со скриптом UniversalJIT26.js (лежит в «Файлы» → HTS → JIT). Запускайте HTS из StikDebug и не закрывайте StikDebug."
        }
        return "Без JIT Java на iOS не запускается. Откройте HTS через StikDebug (или SideStore → Enable JIT) и вернитесь в приложение."
    }
}

/** What a probe of one runtime measured (HTSJava.probeJavaHome). */
struct JavaProbeResult {
    let runtime: JavaRuntime
    let properties: [String: String]
    let startMs: Double
    let sortMs: [Double]
    let compiler: String?
    let compileMs: Int?
    let processors: Int
    let maxMemoryMb: Int

    init(runtime: JavaRuntime, _ raw: [String: Any]) {
        self.runtime = runtime
        properties = raw["properties"] as? [String: String] ?? [:]
        startMs = (raw["startMs"] as? NSNumber)?.doubleValue ?? 0
        sortMs = (raw["sortMs"] as? [NSNumber])?.map(\.doubleValue) ?? []
        compiler = raw["compiler"] as? String
        compileMs = (raw["compileMs"] as? NSNumber)?.intValue
        processors = (raw["processors"] as? NSNumber)?.intValue ?? 0
        maxMemoryMb = (raw["maxMemoryMb"] as? NSNumber)?.intValue ?? 0
    }

    init(runtime: JavaRuntime, properties: [String: String], startMs: Double, sortMs: [Double], compiler: String?,
         compileMs: Int?, processors: Int, maxMemoryMb: Int) {
        self.runtime = runtime
        self.properties = properties
        self.startMs = startMs
        self.sortMs = sortMs
        self.compiler = compiler
        self.compileMs = compileMs
        self.processors = processors
        self.maxMemoryMb = maxMemoryMb
    }

    /**
     * The compiler ran and the sort is compiled-fast: interpreted it takes seconds, compiled ~0.1 s.
     * Not "later rounds faster than the first": OSR compiles the loop inside round one already.
     */
    var jitWorks: Bool {
        guard compiler != nil, (compileMs ?? 0) > 0, let best = sortMs.min() else { return false }
        return best < 400
    }

    var summary: String {
        let p = properties
        var lines = [
            "\(runtime.title): \(p["java.version"] ?? runtime.version), \(p["java.vm.name"] ?? "?") (\(p["java.vm.info"] ?? "?"))",
            "Старт JVM: \(Int(startMs)) мс, ядер \(processors), куча до \(maxMemoryMb) МБ",
            "Сортировка 1 млн чисел, мс: " + sortMs.map { String(Int($0.rounded())) }.joined(separator: " → "),
        ]
        if let compiler { lines.append("Компилятор: \(compiler), \(compileMs ?? 0) мс компиляции") }
        return lines.joined(separator: "\n")
    }
}
