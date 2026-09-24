import Foundation
import HTSCore

/**
 * How one McSkill client starts on iOS: the Android app's LaunchSpec + JvmLauncher for the SDL
 * packs (Forge 1.7.10 with lwjgl3ify 3 on RFB: HiTech, TechnoMagic, Galaxy). The window is SDL3
 * (ours, on ANGLE), GL is gl4es, LWJGL is the iOS 3.4.1 build that replaces the pack's.
 */
struct LaunchPlan {
    let pack: String
    let gameDir: URL
    let runtime: JavaRuntime
    let mainClass: String
    let jvmArgs: [String]
    let gameArgs: [String]
    let environment: [String: String]
    let heapMb: Int
}

enum GameLauncher {
    enum LaunchError: LocalizedError {
        case unsupported(String)
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let text), .missing(let text): return text
            }
        }
    }

    /** What the McSkill launcher adds to every client: its auth server stands in for Mojang's. */
    static let apiArgs = [
        "-Dminecraft.api.env=CUSTOM",
        "-Dminecraft.api.auth=https://auth.mcskill.ru",
        "-Dminecraft.api.auth.host=https://auth.mcskill.ru/sessionserver",
        "-Dminecraft.api.account.host=https://auth.mcskill.ru/sessionserver",
        "-Dminecraft.api.session.host=https://auth.mcskill.ru/sessionserver",
        "-Dminecraft.api.services.host=https://auth.mcskill.ru/sessionserver",
    ]

    /** Options whose value may come as the next argument; the JVM takes them only as opt=value. */
    private static let joinedOptions: Set<String> = [
        "--add-opens", "--add-exports", "--add-reads", "--add-modules", "--enable-native-access",
        "--patch-module", "--limit-modules", "--upgrade-module-path",
    ]

    static var patchJar: URL { GameRuntime.gameDir.appendingPathComponent("hts-lwjgl-patch.jar") }
    static var mioLibPatcher: URL { GameRuntime.gameDir.appendingPathComponent("MioLibPatcher.jar") }
    static var log4jConfig: URL { GameRuntime.gameDir.appendingPathComponent("log4j-rce-patch-1.7.xml") }

    static func plan(profile: ClientProfileInfo, pack: String, session: McSkillSession, runtime: JavaRuntime,
                     heapMb: Int, extraJvmArgs: [String], width: Int, height: Int) throws -> LaunchPlan {
        let gameDir = ClientStore.clientDir(pack)
        let assetsDir = ClientStore.assetsDir(try ClientStore.folderName(profile.assetsDir))
        let args = profile.jvmArgs.map { $0.replacingOccurrences(of: "${cp_separator}", with: ":") }

        let neoForge = profile.mainClass.lowercased().contains("bootstraplauncher")
            || args.contains { $0 == "-p" || $0.hasPrefix("--module-path") }
        if neoForge {
            throw LaunchError.unsupported("NeoForge (\(profile.version)) на iOS пока не запускается: сначала доделываем клиенты 1.7.10 на SDL.")
        }

        var jvm: [String] = []
        var legacyClassPath: [String]?
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("-DlegacyClassPath=") {
                legacyClassPath = splitPath(String(arg.dropFirst("-DlegacyClassPath=".count)))
            } else if arg == "-cp" || arg == "-classpath" {
                i += 1
            } else if joinedOptions.contains(arg), i + 1 < args.count {
                jvm.append("\(arg)=\(args[i + 1])")
                i += 1
            } else if !droppedOnIOS(arg) {
                jvm.append(arg)
            }
            i += 1
        }
        for api in apiArgs {
            let key = String(api[...api.firstIndex(of: "=")!])
            if !jvm.contains(where: { $0.hasPrefix(key) }) { jvm.append(api) }
        }

        let packJars = legacyClassPath ?? expand(profile.classPath, in: gameDir)
        let sdl = packJars.contains { ($0.split(separator: "/").last ?? "").lowercased().hasPrefix("lwjgl-sdl") }
        guard sdl else {
            throw LaunchError.unsupported("\(profile.version) на GLFW (lwjgl3ify 2) на iOS пока не запускается: сначала доделываем клиенты на SDL.")
        }

        // Ours after the pack's: -D given twice takes the last one
        let locale = Locale.current.language.languageCode?.identifier ?? "ru"
        jvm += [
            "-Duser.home=\(gameDir.path)",
            "-Duser.language=\(locale)",
            "-Duser.timezone=\(TimeZone.current.identifier)",
            "-Dlog4j2.formatMsgNoLookups=true",
            "-Dlog4j.configurationFile=\(log4jConfig.path)",
            "-Dfml.earlyprogresswindow=false",
            "-Dloader.disable_forked_guis=true",
            "-Dorg.lwjgl.util.Debug=true",
            "-Dorg.lwjgl.util.DebugLoader=true",
            "-javaagent:\(mioLibPatcher.path)",
            "-Dmiolibpatcher.alc10=true",
        ]
        jvm += GameRuntime.lwjglJvmArgs
        jvm.append("-Djava.class.path=\(try classpath(packJars, gameDir: gameDir))")
        jvm += extraJvmArgs

        let env = GameRuntime.environment.merging([
            "HOME": gameDir.path,
            "TMPDIR": NSTemporaryDirectory(),
            // lwjgl3ify asks for desktop GL 2.1: ANGLE gives ES 3.0, gl4es makes GL 2.1 of it
            "HTS_GL_PROFILE": "es",
            "HTS_GL_MAJOR": "3",
            "HTS_GL_MINOR": "0",
            "HTS_GL_NO_SHARE": "1",
            "HTS_GL_PROC_LIB": GameRuntime.gl4es.path,
            "LIBGL_MIPMAP": "3",
            "LIBGL_NOERROR": "1",
        ]) { _, new in new }

        return LaunchPlan(pack: pack, gameDir: gameDir, runtime: runtime, mainClass: profile.mainClass,
                          jvmArgs: jvm, gameArgs: gameArgs(profile: profile, session: session, gameDir: gameDir,
                                                           assetsDir: assetsDir, width: width, height: height),
                          environment: env, heapMb: heapMb)
    }

    /** Configs edited for iOS, then the JVM with the game's main on its thread. */
    static func launch(_ plan: LaunchPlan) throws {
        prepareConfig(plan)
        try? FileManager.default.removeItem(at: JavaRuntimes.logURL)
        let shown = plan.jvmArgs + [plan.mainClass] + redacted(plan.gameArgs)
        AppLog.info("Launch \(plan.pack) on \(plan.runtime.title), \(plan.heapMb) MB:\n" + shown.joined(separator: "\n"))
        try HTSJava.launch(javaHome: plan.runtime.home.path, heapMb: plan.heapMb, jvmArgs: plan.jvmArgs,
                           mainClass: plan.mainClass, args: plan.gameArgs, environment: plan.environment,
                           log: JavaRuntimes.logURL.path)
    }

    private static func redacted(_ args: [String]) -> [String] {
        args.enumerated().map { i, arg in i > 0 && args[i - 1] == "--accessToken" ? "<session>" : arg }
    }

    /**
     * PC options that break or mean nothing here: heap (the app's setting), native paths (the iOS
     * builds), macOS's first-thread flag, pre-touching the heap, NUMA, GCs other than G1, large
     * pages, heap dumps, the 1.7.10 log4j config (ours closes the lookup hole), compact object
     * headers (they need the compressed class space iOS can't reserve without extended VA).
     */
    private static func droppedOnIOS(_ arg: String) -> Bool {
        let prefixes = ["-Xms", "-Xmx", "-Xmn", "-Djava.library.path=", "-Dorg.lwjgl.librarypath=", "-XX:HeapDumpPath",
                        "-XX:+UseLargePages", "-XX:LargePageSizeInBytes", "-XX:+UseTransparentHugePages",
                        "-Dlog4j.configurationFile="]
        if prefixes.contains(where: { arg.hasPrefix($0) }) { return true }
        return ["-XstartOnFirstThread", "-XX:+AlwaysPreTouch", "-XX:+UseNUMA", "-XX:+UseZGC", "-XX:+ZGenerational",
                "-XX:-ZGenerational", "-XX:+UseShenandoahGC", "-XX:+UseParallelGC", "-XX:+UseSerialGC",
                "-XX:+UseCompactObjectHeaders"].contains(arg)
    }

    private static func splitPath(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == ":" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "/") }
            .filter { !$0.isEmpty }
    }

    /**
     * Class path entries as the launcher expands them: a folder gives every .jar below it, depth
     * first in name order as Windows lists them (NTFS sorts by upper-cased name).
     */
    static func expand(_ entries: [String], in packDir: URL) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ rel: String) {
            if seen.insert(rel).inserted { out.append(rel) }
        }
        func collect(_ dir: URL, _ rel: String) {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .sorted { $0.uppercased() < $1.uppercased() }
            for name in names {
                let child = dir.appendingPathComponent(name)
                let childRel = rel.isEmpty ? name : "\(rel)/\(name)"
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir)
                if isDir.boolValue { collect(child, childRel) } else if name.hasSuffix(".jar") { add(childRel) }
            }
        }
        for entry in entries {
            var rel = entry.replacingOccurrences(of: "\\", with: "/")
            while rel.hasPrefix("/") { rel.removeFirst() }
            while rel.hasSuffix("/") { rel.removeLast() }
            let url = packDir.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                collect(url, rel)
            } else {
                add(rel)
            }
        }
        return out
    }

    /**
     * Our LWJGL patch, the iOS LWJGL 3.4.1 jars, then the pack's jars in order without the LWJGL
     * modules those replace and without desktop natives.
     */
    private static func classpath(_ packJars: [String], gameDir: URL) throws -> String {
        var entries = [patchJar.path]
        let ours = GameRuntime.jars(in: GameRuntime.lwjglDir).filter { !$0.hasSuffix("/lwjgl-lwjglx.jar") }
        entries += ours
        let modules = Set(ours.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent })
        var missing: [String] = []
        for rel in packJars {
            let name = String(rel.split(separator: "/").last ?? "")
            if isReplacedLwjgl(name, modules) || PathRules.desktopOnly(rel) { continue }
            let path = gameDir.appendingPathComponent(rel).path
            guard FileManager.default.fileExists(atPath: path) else {
                missing.append(rel)
                continue
            }
            if !entries.contains(path) { entries.append(path) }
        }
        if !missing.isEmpty { AppLog.error("Classpath entries not found: \(missing)") }
        return entries.joined(separator: ":")
    }

    /** lwjgl-glfw-3.3.3.jar or libraries/lwjgl/lwjgl-glfw.jar: a module of ours by name. */
    private static func isReplacedLwjgl(_ name: String, _ modules: Set<String>) -> Bool {
        guard name.hasPrefix("lwjgl"), name.hasSuffix(".jar") else { return false }
        let base = String(name.dropLast(4))
        if modules.contains(base) { return true }
        guard let dash = base.lastIndex(of: "-"), base.index(after: dash) < base.endIndex,
              base[base.index(after: dash)].isNumber else { return false }
        return modules.contains(String(base[..<dash]))
    }

    /** play.py's add_client_args, then the profile's client_args except the ones set here. */
    private static func gameArgs(profile: ClientProfileInfo, session: McSkillSession, gameDir: URL, assetsDir: URL,
                                 width: Int, height: Int) -> [String] {
        let nick = session.profile.username
        let properties = "{\"skinURL\":[\"https://skins.mcskill.net/MinecraftSkins/\(nick).png\"],"
            + "\"cloakURL\":[\"https://skins.mcskill.net/MinecraftCloaks/\(nick).png\"]}"
        var args = [
            "--username", nick,
            "--uuid", session.profile.uuid.replacingOccurrences(of: "-", with: ""),
            "--accessToken", session.id,
            "--userType", "mojang",
            "--userProperties", properties,
            "--assetIndex", profile.assetIndex.isEmpty ? profile.version : profile.assetIndex,
            "--version", profile.version,
            "--gameDir", gameDir.path,
            "--assetsDir", assetsDir.path,
            "--resourcePackDir", gameDir.appendingPathComponent("resourcepacks").path,
            "--width", String(width),
            "--height", String(height),
        ]
        let set = Set(args.filter { $0.hasPrefix("--") })
        let extra = profile.clientArgs
        var i = 0
        while i < extra.count {
            let arg = extra[i]
            let key = arg.split(separator: "=", maxSplits: 1).first.map(String.init) ?? arg
            if set.contains(key) {
                if !arg.contains("="), i + 1 < extra.count, !extra[i + 1].hasPrefix("--") { i += 1 }
            } else {
                args.append(arg)
            }
            i += 1
        }
        return args
    }

    // MARK: - configs

    /**
     * What the PC config ships with that breaks here: lwjgl3ify's shared context (one EGL context,
     * no loading-screen baton yet) and XDG desktop entry, Forge's splash, AwesomeLoadingScreen's
     * own window, the optional-mods chooser; idle FPS when minimized.
     */
    private static func prepareConfig(_ plan: LaunchPlan) {
        setForgeOption(plan, "config/lwjgl3ify.cfg", category: "openglcontext", key: "B:sharedContext=", value: "false")
        setForgeOption(plan, "config/lwjgl3ify.cfg", category: "window", key: "B:linuxCreateAppDesktopEntry=", value: "false")
        setOption(plan, "config/splash.properties", key: "enabled=", value: "false", appendIfAbsent: true)
        setOption(plan, "config/als/config.cfg", key: "B:useMinecraft=", value: "false", appendIfAbsent: false)
        setOption(plan, "config/als.cfg", key: "B:useMinecraft=", value: "false", appendIfAbsent: false)
        setOption(plan, "config/FpsReducer/FpsReducer.cfg", key: "B:reducingInBackground=", value: "true", appendIfAbsent: false)
        setOption(plan, "optional.txt", key: "timer-time=", value: "0", appendIfAbsent: false)
    }

    /** Writes an edited config; for a server file the ledger remembers it stands for the original. */
    private static func writePatched(_ plan: LaunchPlan, _ rel: String, original: String, existed: Bool, patched: String) {
        let url = plan.gameDir.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? patched.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        if existed {
            PatchLedger.record(pack: plan.pack, path: rel, before: Blake3.hash(Data(original.utf8)),
                               after: Blake3.hash(Data(patched.utf8)))
        }
    }

    /**
     * key + value inside `category { ... }` of a Forge config: replaced in place, added before the
     * category's closing brace when absent (the category is created if needed). Copies of the key
     * outside any category are dropped: Forge rejects the whole file for them.
     */
    private static func setForgeOption(_ plan: LaunchPlan, _ rel: String, category: String, key: String, value: String) {
        let url = plan.gameDir.appendingPathComponent(rel)
        let existed = FileManager.default.fileExists(atPath: url.path)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = text.components(separatedBy: "\n")
        var depth = 0
        var inCategory = false, found = false
        var categoryEnd = -1
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            defer { i += 1 }
            if trimmed.hasPrefix("#") { continue }
            if trimmed.hasSuffix("{") {
                if depth == 0 && trimmed.dropLast().trimmingCharacters(in: .whitespaces) == category { inCategory = true }
                depth += 1
                continue
            }
            if trimmed == "}" {
                depth -= 1
                if depth == 0 && inCategory {
                    inCategory = false
                    categoryEnd = i
                }
                continue
            }
            guard trimmed.hasPrefix(key) else { continue }
            if depth == 0 {
                lines.remove(at: i)
                i -= 1
            } else if inCategory, let range = lines[i].range(of: key) {
                lines[i] = String(lines[i][..<range.lowerBound]) + key + value
                found = true
            }
        }
        if !found {
            if categoryEnd >= 0 {
                lines.insert("    " + key + value, at: categoryEnd)
            } else {
                if lines.last == "" { lines.removeLast() }
                lines += ["\(category) {", "    " + key + value, "}", ""]
            }
        }
        let patched = lines.joined(separator: "\n")
        if patched != text { writePatched(plan, rel, original: text, existed: existed, patched: patched) }
    }

    /** key + value on the line starting with key; appended when absent if appendIfAbsent. */
    private static func setOption(_ plan: LaunchPlan, _ rel: String, key: String, value: String, appendIfAbsent: Bool) {
        let url = plan.gameDir.appendingPathComponent(rel)
        let existed = FileManager.default.fileExists(atPath: url.path)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var found = false
        var lines = text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key), let range = line.range(of: key) else { return line }
            found = true
            return String(line[..<range.lowerBound]) + key + value
        }
        if !found {
            guard appendIfAbsent else { return }
            if lines.last == "" { lines.removeLast() }
            lines += [key + value, ""]
        }
        let patched = lines.joined(separator: "\n")
        if patched != text { writePatched(plan, rel, original: text, existed: existed, patched: patched) }
    }
}
