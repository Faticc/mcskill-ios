import Foundation

/** Where clients live: Documents/clients/<client_dir>, Documents/assets/<assets_dir>, records in Documents/installed. */
public enum ClientStore {
    public static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public static var clientsDir: URL { documents.appendingPathComponent("clients", isDirectory: true) }
    public static var assetsRoot: URL { documents.appendingPathComponent("assets", isDirectory: true) }
    public static var installedRoot: URL { documents.appendingPathComponent("installed", isDirectory: true) }

    public static func clientDir(_ pack: String) -> URL { clientsDir.appendingPathComponent(pack, isDirectory: true) }
    public static func assetsDir(_ name: String) -> URL { assetsRoot.appendingPathComponent(name, isDirectory: true) }
    public static func record(_ pack: String) -> URL { installedRoot.appendingPathComponent(pack, isDirectory: true) }

    /** client_dir / assets_dir of the server as a single safe folder name. */
    public static func folderName(_ name: String) throws -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._ -")
        guard !name.isEmpty, !name.hasPrefix("."), name.unicodeScalars.allSatisfy(allowed.contains) else {
            throw SyncError.message("Недопустимое имя папки клиента: \(name)")
        }
        return name
    }

    /** The profile the last successful sync installed, for the launch and the "installed" line. */
    public static func installedProfile(_ pack: String) -> ClientProfileInfo? {
        guard let data = try? Data(contentsOf: record(pack).appendingPathComponent("profile.json")) else { return nil }
        return try? JSONDecoder().decode(ClientProfileInfo.self, from: data)
    }

    static func saveProfile(_ profile: ClientProfileInfo, pack: String) {
        let dir = record(pack)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(profile) {
            try? data.write(to: dir.appendingPathComponent("profile.json"), options: .atomic)
        }
    }
}

public enum SyncError: LocalizedError {
    case message(String)
    case diskSpace(download: Int64, required: Int64, available: Int64)

    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .diskSpace: return "Недостаточно места на диске"
        }
    }
}

/**
 * Config files the app edits for iOS (lwjgl3ify.cfg, splash.properties...). Their hash no longer
 * matches the server's and the sync would download them again before every start; the ledger
 * remembers "this local content is that server file after our edit". A real update on the server
 * still comes through (then the launch edits the new file again). Lines: path@local=original.
 */
public enum PatchLedger {
    private static let lock = NSLock()

    static func file(_ pack: String) -> URL {
        ClientStore.record(pack).appendingPathComponent("patches.txt")
    }

    public static func load(_ pack: String) -> [String: String] {
        guard let text = try? String(contentsOf: file(pack), encoding: .utf8) else { return [:] }
        var map: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let eq = line.lastIndex(of: "=") else { continue }
            map[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return map
    }

    /** Records an edit of `path`: content hash before and after. */
    public static func record(pack: String, path: String, before: String, after: String) {
        lock.lock()
        defer { lock.unlock() }
        var map = load(pack)
        // An edit of an edited file keeps pointing at the server's original
        let original = map["\(path)@\(before)"] ?? before
        map["\(path)@\(after)"] = original
        let text = map.map { $0.key + "=" + $0.value }.sorted().joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: ClientStore.record(pack), withIntermediateDirectories: true)
        try? text.write(to: file(pack), atomically: true, encoding: .utf8)
    }

    /** The server hash a local file stands for: its original if we edited it, else its own. */
    static func original(_ ledger: [String: String], _ path: String, _ local: String) -> String {
        ledger["\(path)@\(local)"] ?? local
    }
}

/** Path matching of the McSkill launcher's sync, plus what iOS never needs. */
public enum PathRules {
    /** "mods" covers "mods" and "mods/x.jar", not "modsx": the launcher's prefix rule. */
    public static func under(_ path: String, _ prefix: String) -> Bool {
        var p = prefix
        while p.hasSuffix("/") { p.removeLast() }
        return path == p || path.hasPrefix(p + "/")
    }

    /** Under one of the update paths and none of the exclusions. */
    public static func managed(_ path: String, include: [String], exclude: [String]) -> Bool {
        guard include.contains(where: { under(path, $0) }) else { return false }
        return !exclude.contains(where: { under(path, $0) })
    }

    private static let desktopNativeJar = try! NSRegularExpression(
        pattern: "^.*(-natives-(windows|macos|osx|linux)[^/]*|-(linux|macosx|windows)-(x86|x86_64|arm64|armhf|ppc64le))\\.jar$",
        options: [.caseInsensitive])

    /**
     * Files of a PC client that are useless on iOS and are neither downloaded nor deleted:
     * desktop natives. The game gets iOS builds from the app instead.
     */
    public static func desktopOnly(_ path: String) -> Bool {
        let lower = path.lowercased()
        if lower.hasPrefix("natives/") { return true }
        for ext in [".dll", ".exe", ".dylib", ".jnilib", ".so"] where lower.hasSuffix(ext) { return true }
        let name = String(lower.split(separator: "/").last ?? "")
        return desktopNativeJar.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    /** Our own files inside a client folder; the sync never touches them. */
    public static func ours(_ path: String) -> Bool {
        path.hasPrefix(".hts/") || path.hasSuffix(".part") || path == "hts_launch.json"
    }

    /** Manifest path as a safe relative path with forward slashes, or nil. */
    public static func normalize(_ path: String) -> String? {
        var p = path.replacingOccurrences(of: "\\", with: "/")
        while p.hasPrefix("/") { p.removeFirst() }
        if p.isEmpty { return nil }
        for segment in p.split(separator: "/", omittingEmptySubsequences: false) {
            if segment == ".." || segment == "." || segment.isEmpty { return nil }
        }
        return p
    }
}

/**
 * BLAKE3 of local files remembered by size and modification time, so a check of an unchanged
 * client takes milliseconds. Lines: hash TAB size TAB mtime TAB path.
 */
final class HashIndex: @unchecked Sendable {
    private struct Entry {
        let hash: String
        let size: Int64
        let mtime: Int64
    }

    private let file: URL
    private var entries: [String: Entry] = [:]
    private var dirty = false
    private let lock = NSLock()

    init(file: URL) {
        self.file = file
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, let size = Int64(parts[1]), let mtime = Int64(parts[2]) else { continue }
            entries[String(parts[3])] = Entry(hash: String(parts[0]), size: size, mtime: mtime)
        }
    }

    static func stat(_ url: URL) -> (size: Int64, mtime: Int64)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value,
              let date = attrs[.modificationDate] as? Date else { return nil }
        return (size, Int64(date.timeIntervalSince1970 * 1000))
    }

    func put(_ path: String, _ url: URL, _ hash: String) {
        guard let s = HashIndex.stat(url) else { return }
        lock.lock()
        entries[path] = Entry(hash: hash, size: s.size, mtime: s.mtime)
        dirty = true
        lock.unlock()
    }

    func remove(_ path: String) {
        lock.lock()
        if entries.removeValue(forKey: path) != nil { dirty = true }
        lock.unlock()
    }

    /** Hash of a local file, from the cache when size and time are unchanged. */
    func hash(_ path: String, _ url: URL, trustCache: Bool) throws -> String {
        if trustCache, let s = HashIndex.stat(url) {
            lock.lock()
            let entry = entries[path]
            lock.unlock()
            if let entry, entry.size == s.size, entry.mtime == s.mtime { return entry.hash }
        }
        let hash = try Blake3.hashFile(url)
        put(path, url, hash)
        return hash
    }

    func save() {
        lock.lock()
        defer { lock.unlock() }
        guard dirty else { return }
        var text = ""
        for (path, e) in entries { text += "\(e.hash)\t\(e.size)\t\(e.mtime)\t\(path)\n" }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil { dirty = false }
    }
}

/** Counters of a running sync; read from any thread for the progress bar. */
public final class SyncProgress: @unchecked Sendable {
    public enum Phase: Sendable { case preparing, checking, downloading, deleting, done }

    private let lock = NSLock()
    private var _phase = Phase.preparing
    private var _checked = 0, _toCheck = 0
    private var _downloadedFiles = 0, _filesToDownload = 0
    private var _downloadedBytes: Int64 = 0, _bytesToDownload: Int64 = 0

    public init() {}

    public struct Snapshot: Sendable {
        public var phase: Phase
        public var checked: Int, toCheck: Int
        public var downloadedFiles: Int, filesToDownload: Int
        public var downloadedBytes: Int64, bytesToDownload: Int64

        public init(phase: Phase, checked: Int, toCheck: Int, downloadedFiles: Int, filesToDownload: Int,
                    downloadedBytes: Int64, bytesToDownload: Int64) {
            self.phase = phase
            self.checked = checked
            self.toCheck = toCheck
            self.downloadedFiles = downloadedFiles
            self.filesToDownload = filesToDownload
            self.downloadedBytes = downloadedBytes
            self.bytesToDownload = bytesToDownload
        }
    }

    public var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(phase: _phase, checked: _checked, toCheck: _toCheck, downloadedFiles: _downloadedFiles,
                        filesToDownload: _filesToDownload, downloadedBytes: _downloadedBytes,
                        bytesToDownload: _bytesToDownload)
    }

    func update(_ body: (SyncProgress) -> Void) {
        lock.lock()
        body(self)
        lock.unlock()
    }

    func set(phase: Phase) { update { $0._phase = phase } }
    func set(toCheck: Int) { update { $0._toCheck = toCheck } }
    func checkedOne() { update { $0._checked += 1 } }
    func set(filesToDownload: Int, bytes: Int64) { update { $0._filesToDownload = filesToDownload; $0._bytesToDownload = bytes } }
    func downloadedOne() { update { $0._downloadedFiles += 1 } }
    func add(bytes: Int64) { update { $0._downloadedBytes += bytes } }
}

/**
 * Installs or updates one McSkill client the way the McSkill launcher does on the PC (a port of
 * the Android app's ClientSync):
 * 1. profile and manifests of the client and of its assets folder;
 * 2. BLAKE3 of local files: every file of the assets folder, of the client folder only the ones
 *    under update_paths minus exclusion_paths (the rest is the player's);
 * 3. download what is missing or differs: a client file that exists but isn't managed is left
 *    alone, and with INTEGRITY_MODE_BYPASS existing files are never compared;
 * 4. with the standard integrity mode delete managed files the manifest doesn't have.
 * Files come from the manifest's CDN node (base/hh/hash, resumed from a .part and hashed on the
 * fly), then from a fallback node, then as gRPC streams. Desktop natives are skipped.
 */
public final class ClientSync: @unchecked Sendable {
    public static let reserveBytes: Int64 = 512 << 20
    private static let httpParallel = 6
    private static let httpAttempts = 3
    private static let grpcBatchFiles = 40
    private static let grpcBatchBytes: Int64 = 64 << 20

    public struct Result: Sendable {
        public var profile: ClientProfileInfo
        public var pack: String
        public var downloaded: Int
        public var deleted: Int
        public var bytes: Int64
        public var skipped: Int
    }

    private let clientId: Int
    private let session: String
    private let api: McSkillAPI
    private let fullCheck: Bool
    public let progress = SyncProgress()

    /** - Parameter fullCheck: hash every file again instead of trusting the cache */
    public init(clientId: Int, session: String, fullCheck: Bool = false, api: McSkillAPI = .shared) {
        self.clientId = clientId
        self.session = session
        self.fullCheck = fullCheck
        self.api = api
    }

    public func run(profile known: ClientProfileInfo? = nil) async throws -> Result {
        let started = Date()
        progress.set(phase: .preparing)
        var profile = known
        if profile == nil { profile = try await api.clientProfile(id: clientId, session: session) }
        guard let profile else { throw SyncError.message("Нет профиля клиента") }
        let pack = try ClientStore.folderName(profile.clientDir)
        let assetsName = try ClientStore.folderName(profile.assetsDir)

        async let clientTreeCall = api.fileTree(clientId: clientId, session: session)
        async let assetTreeCall = api.assetFileTree(assetDir: profile.assetsDir, session: session)
        let clientTree = try await clientTreeCall
        let assetTree = try await assetTreeCall
        try Task.checkCancellation()

        let record = ClientStore.record(pack)
        let client = Tree(sync: self, root: ClientStore.clientDir(pack), manifest: clientTree,
                          index: HashIndex(file: record.appendingPathComponent("client.idx")),
                          include: profile.updatePaths, exclude: profile.exclusionPaths, isClient: true,
                          clientId: clientId, assetDir: nil)
        client.ledger = PatchLedger.load(pack)
        let assets = Tree(sync: self, root: ClientStore.assetsDir(assetsName), manifest: assetTree,
                          index: HashIndex(file: record.appendingPathComponent("assets.idx")),
                          include: [], exclude: [], isClient: false, clientId: nil, assetDir: profile.assetsDir)

        progress.set(phase: .checking)
        client.list()
        assets.list()
        progress.set(toCheck: client.toHash.count + assets.toHash.count)
        try await client.hashLocal()
        try await assets.hashLocal()
        try Task.checkCancellation()

        let bypass = profile.integrityBypass
        client.plan(bypass: bypass, deleteExtras: !bypass)
        assets.plan(bypass: false, deleteExtras: !bypass)
        AppLog.info("Sync \(pack): download \(client.downloads.count)+\(assets.downloads.count), delete \(client.deletes.count)+\(assets.deletes.count), skipped \(client.skipped + assets.skipped)")

        let bytes = client.downloadBytes + assets.downloadBytes
        let required = bytes - client.partialBytes - assets.partialBytes + ClientSync.reserveBytes
        let available = ClientSync.freeSpace()
        if bytes > 0 && available < required {
            throw SyncError.diskSpace(download: bytes, required: required, available: available)
        }

        progress.set(phase: .downloading)
        progress.set(filesToDownload: client.downloads.count + assets.downloads.count, bytes: bytes)
        defer {
            client.index.save()
            assets.index.save()
        }
        try await client.download()
        try await assets.download()
        progress.set(phase: .deleting)
        client.deleteExtras()
        assets.deleteExtras()

        ClientStore.saveProfile(profile, pack: pack)
        progress.set(phase: .done)
        let result = Result(profile: profile, pack: pack, downloaded: client.downloads.count + assets.downloads.count,
                            deleted: client.deletes.count + assets.deletes.count, bytes: bytes,
                            skipped: client.skipped + assets.skipped)
        AppLog.info("Sync \(pack) done: \(result.downloaded) files, \(bytes) bytes, \(result.deleted) deleted in \(Int(Date().timeIntervalSince(started)))s")
        return result
    }

    static func freeSpace() -> Int64 {
        let values = try? ClientStore.documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }

    // MARK: - one folder

    struct DownloadTask: Sendable {
        let path: String
        let hash: String
        let size: Int64
        let file: URL
        var part: URL { URL(fileURLWithPath: file.path + ".part") }
    }

    final class Tree: @unchecked Sendable {
        unowned let sync: ClientSync
        let root: URL
        let manifest: FileTree
        let index: HashIndex
        let include: [String]
        let exclude: [String]
        let isClient: Bool
        let clientId: Int?
        let assetDir: String?

        /** Edits of the app (client folder only): local hash -> server hash. */
        var ledger: [String: String] = [:]
        var localPaths = Set<String>()
        var localHashes: [String: String] = [:]
        var downloads: [DownloadTask] = []
        var deletes: [String] = []
        var skipped = 0
        private let lock = NSLock()

        init(sync: ClientSync, root: URL, manifest: FileTree, index: HashIndex, include: [String], exclude: [String],
             isClient: Bool, clientId: Int?, assetDir: String?) {
            self.sync = sync
            self.root = root
            self.manifest = manifest
            self.index = index
            self.include = include
            self.exclude = exclude
            self.isClient = isClient
            self.clientId = clientId
            self.assetDir = assetDir
        }

        func list() {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                         options: []) else { return }
            let base = root.standardizedFileURL.path + "/"
            for case let url as URL in e {
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(base) else { continue }
                let rel = String(path.dropFirst(base.count))
                if rel == ".hts" || rel.hasPrefix(".hts/") {
                    if rel == ".hts" { e.skipDescendants() }
                    continue
                }
                let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                if isFile && !PathRules.ours(rel) { localPaths.insert(rel) }
            }
        }

        lazy var toHash: [String] = localPaths.filter {
            !isClient || PathRules.managed($0, include: include, exclude: exclude)
        }

        func hashLocal() async throws {
            let paths = toHash
            let trust = !sync.fullCheck
            let workers = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount))
            try await withThrowingTaskGroup(of: (String, String).self) { group in
                var next = 0
                func add() {
                    guard next < paths.count else { return }
                    let path = paths[next]
                    next += 1
                    group.addTask { [root, index] in
                        try Task.checkCancellation()
                        let url = root.appendingPathComponent(path)
                        // Unreadable counts as damaged: downloaded again
                        let hash = (try? index.hash(path, url, trustCache: trust)) ?? "unreadable"
                        return (path, hash)
                    }
                }
                for _ in 0..<workers { add() }
                while let (path, hash) = try await group.next() {
                    localHashes[path] = PatchLedger.original(ledger, path, hash)
                    sync.progress.checkedOne()
                    add()
                }
            }
        }

        func plan(bypass: Bool, deleteExtras: Bool) {
            var listed = Set<String>()
            for node in manifest.files where !node.isDirectory {
                guard let path = PathRules.normalize(node.path) else { continue }
                listed.insert(path)
                if PathRules.desktopOnly(path) {
                    skipped += 1
                    continue
                }
                let task = DownloadTask(path: path, hash: node.hash, size: node.size,
                                        file: root.appendingPathComponent(path))
                if isClient {
                    if !localPaths.contains(path) {
                        downloads.append(task)
                    } else if !bypass, let local = localHashes[path], !node.hash.isEmpty, local != node.hash {
                        // Present but not managed (no local hash): the player's file, left alone
                        downloads.append(task)
                    }
                } else {
                    let local = localHashes[path]
                    if local == nil || (!node.hash.isEmpty && local != node.hash) { downloads.append(task) }
                }
            }
            guard deleteExtras else { return }
            for path in localPaths where !listed.contains(path) && !PathRules.desktopOnly(path) {
                if isClient && !PathRules.managed(path, include: include, exclude: exclude) { continue }
                deletes.append(path)
            }
        }

        var downloadBytes: Int64 { downloads.reduce(0) { $0 + $1.size } }

        var partialBytes: Int64 {
            downloads.reduce(0) { sum, t in
                guard let s = HashIndex.stat(t.part), s.size <= t.size else { return sum }
                return sum + s.size
            }
        }

        func download() async throws {
            guard !downloads.isEmpty else { return }
            var remaining = downloads.filter { !$0.hash.isEmpty }
            let hashless = downloads.filter { $0.hash.isEmpty }
            if let base = manifest.baseURL, !base.isEmpty, !remaining.isEmpty {
                remaining = try await httpPhase(base: base, remaining)
                var excluded = Set<String>()
                if let node = manifest.nodeId, !node.isEmpty { excluded.insert(node) }
                var round = 0
                while !remaining.isEmpty && round < 3 {
                    round += 1
                    try Task.checkCancellation()
                    guard let fallback = try? await sync.api.fallbackNode(clientId: clientId, assetDir: assetDir,
                                                                          excluding: excluded, session: sync.session)
                    else { break }
                    AppLog.info("Fallback node \(fallback.nodeId) for \(remaining.count) files")
                    excluded.insert(fallback.nodeId)
                    remaining = try await httpPhase(base: fallback.baseURL, remaining)
                }
            }
            remaining += hashless
            if !remaining.isEmpty {
                AppLog.info("gRPC for \(remaining.count) files of \(root.lastPathComponent)")
                remaining = try await grpcPhase(remaining)
            }
            if let first = remaining.first {
                throw SyncError.message("Не удалось скачать \(remaining.count) файл(ов), например \(first.path)")
            }
        }

        /** Parallel HTTP downloads from one node; returns what still failed. */
        private func httpPhase(base: String, _ tasks: [DownloadTask]) async throws -> [DownloadTask] {
            let prefix = base.hasSuffix("/") ? String(base.dropLast()) : base
            var failed: [DownloadTask] = []
            try await withThrowingTaskGroup(of: DownloadTask?.self) { group in
                var next = 0
                func add() {
                    guard next < tasks.count else { return }
                    let task = tasks[next]
                    next += 1
                    group.addTask { [self] in
                        for attempt in 1...ClientSync.httpAttempts {
                            try Task.checkCancellation()
                            do {
                                let url = URL(string: "\(prefix)/\(task.hash.prefix(2))/\(task.hash)")!
                                try await fetch(url, task)
                                sync.progress.downloadedOne()
                                return nil
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                AppLog.error("Download \(task.path) attempt \(attempt): \(error.localizedDescription)")
                                if attempt < ClientSync.httpAttempts {
                                    try await Task.sleep(nanoseconds: UInt64(500_000_000) << attempt)
                                }
                            }
                        }
                        return task
                    }
                }
                for _ in 0..<ClientSync.httpParallel { add() }
                while let result = try await group.next() {
                    if let result { failed.append(result) }
                    add()
                }
            }
            return failed
        }

        private func fetch(_ url: URL, _ task: DownloadTask) async throws {
            let fm = FileManager.default
            try fm.createDirectory(at: task.part.deletingLastPathComponent(), withIntermediateDirectories: true)
            var have = HashIndex.stat(task.part)?.size ?? 0
            if have > task.size {
                try? fm.removeItem(at: task.part)
                have = 0
            }
            var hasher = Blake3()
            if have > 0 { try feed(&hasher, task.part, have) }
            sync.progress.add(bytes: have)
            var counted = have
            do {
                if have < task.size || task.size == 0 {
                    let received = try await StreamingDownload.run(url: url, from: have, to: task.part) { data, restarted in
                        if restarted {
                            hasher = Blake3()
                            self.sync.progress.add(bytes: -counted)
                            counted = 0
                        }
                        hasher.update(data)
                        counted += Int64(data.count)
                        self.sync.progress.add(bytes: Int64(data.count))
                    }
                    _ = received
                }
                try finish(task, hasher.hexDigest())
            } catch {
                sync.progress.add(bytes: -counted)
                throw error
            }
        }

        /** Size and hash check, then the .part replaces the file. A bad .part is dropped. */
        private func finish(_ task: DownloadTask, _ hash: String) throws {
            let fm = FileManager.default
            let size = HashIndex.stat(task.part)?.size ?? -1
            if size != task.size || (!task.hash.isEmpty && hash != task.hash) {
                try? fm.removeItem(at: task.part)
                throw SyncError.message("corrupted download of \(task.path) (size \(size)/\(task.size))")
            }
            if fm.fileExists(atPath: task.file.path) { try fm.removeItem(at: task.file) }
            try fm.moveItem(at: task.part, to: task.file)
            index.put(task.path, task.file, hash)
        }

        private func feed(_ hasher: inout Blake3, _ url: URL, _ length: Int64) throws {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var left = length
            while left > 0 {
                let piece = try handle.read(upToCount: Int(min(256 * 1024, left))) ?? Data()
                if piece.isEmpty { break }
                hasher.update(piece)
                left -= Int64(piece.count)
            }
        }

        /** The files as gRPC streams in small batches (big streams get reset by the server). */
        private func grpcPhase(_ tasks: [DownloadTask]) async throws -> [DownloadTask] {
            var left = tasks
            for attempt in 1...3 where !left.isEmpty {
                var failed: [DownloadTask] = []
                for batch in batches(left) {
                    try Task.checkCancellation()
                    failed += await grpcBatch(batch)
                }
                left = failed
                if !left.isEmpty && attempt < 3 { try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(attempt)) }
            }
            return left
        }

        private func batches(_ tasks: [DownloadTask]) -> [[DownloadTask]] {
            var out: [[DownloadTask]] = []
            var current: [DownloadTask] = []
            var bytes: Int64 = 0
            for t in tasks {
                if !current.isEmpty && (current.count >= ClientSync.grpcBatchFiles || bytes + t.size > ClientSync.grpcBatchBytes) {
                    out.append(current)
                    current = []
                    bytes = 0
                }
                current.append(t)
                bytes += t.size
            }
            if !current.isEmpty { out.append(current) }
            return out
        }

        private func grpcBatch(_ batch: [DownloadTask]) async -> [DownloadTask] {
            let byPath = Dictionary(batch.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            var done = Set<String>()
            var current: DownloadTask?
            var handle: FileHandle?
            var hasher = Blake3()
            var counted: Int64 = 0
            do {
                let stream = sync.api.downloadFiles(clientId: clientId, assetDir: assetDir, paths: batch.map(\.path),
                                                    session: sync.session)
                for try await chunk in stream {
                    try Task.checkCancellation()
                    guard let path = PathRules.normalize(chunk.path) else { continue }
                    if current?.path != path {
                        try handle?.close()
                        guard let next = byPath[path] else { throw SyncError.message("unexpected file \(chunk.path)") }
                        current = next
                        let fm = FileManager.default
                        try fm.createDirectory(at: next.part.deletingLastPathComponent(), withIntermediateDirectories: true)
                        fm.createFile(atPath: next.part.path, contents: nil)
                        handle = try FileHandle(forWritingTo: next.part)
                        hasher = Blake3()
                        counted = 0
                    }
                    try handle?.write(contentsOf: chunk.data)
                    hasher.update(chunk.data)
                    counted += Int64(chunk.data.count)
                    sync.progress.add(bytes: Int64(chunk.data.count))
                    if chunk.isLast, let task = current {
                        try handle?.close()
                        handle = nil
                        try finish(task, hasher.hexDigest())
                        sync.progress.downloadedOne()
                        done.insert(task.path)
                        current = nil
                        counted = 0
                    }
                }
            } catch {
                AppLog.error("gRPC batch of \(batch.count) failed after \(done.count): \(error.localizedDescription)")
                sync.progress.add(bytes: -counted)
            }
            try? handle?.close()
            return batch.filter { !done.contains($0.path) }
        }

        func deleteExtras() {
            let fm = FileManager.default
            let rootPath = root.standardizedFileURL.path
            for path in deletes {
                let url = root.appendingPathComponent(path)
                if (try? fm.removeItem(at: url)) != nil || !fm.fileExists(atPath: url.path) { index.remove(path) }
                // Empty folders left behind go too, up to the root
                var dir = url.deletingLastPathComponent()
                while dir.standardizedFileURL.path != rootPath,
                      dir.standardizedFileURL.path.hasPrefix(rootPath),
                      (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
                    try? fm.removeItem(at: dir)
                    dir = dir.deletingLastPathComponent()
                }
            }
        }
    }
}

/**
 * One HTTP download into a .part file, resumed with Range from `offset`; every received piece goes
 * to `onData` (restarted = the server ignored the Range and sent the whole file again).
 */
final class StreamingDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let part: URL
    private let offset: Int64
    private let onData: (Data, Bool) -> Void
    private var handle: FileHandle?
    private var continuation: CheckedContinuation<Int64, Error>?
    private var received: Int64 = 0
    private var failure: Error?

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private init(part: URL, offset: Int64, onData: @escaping (Data, Bool) -> Void) {
        self.part = part
        self.offset = offset
        self.onData = onData
    }

    static func run(url: URL, from offset: Int64, to part: URL,
                    onData: @escaping (Data, Bool) -> Void) async throws -> Int64 {
        let download = StreamingDownload(part: part, offset: offset, onData: onData)
        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("McSkill-iOS", forHTTPHeaderField: "User-Agent")
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        let task = session.dataTask(with: request)
        task.delegate = download
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let fm = FileManager.default
        do {
            if code == 206 && offset > 0 {
                handle = try FileHandle(forWritingTo: part)
                try handle?.seekToEnd()
            } else if code == 200 {
                fm.createFile(atPath: part.path, contents: nil)
                handle = try FileHandle(forWritingTo: part)
                onData(Data(), true)
            } else {
                if code == 416 { try? fm.removeItem(at: part) }
                throw SyncError.message("HTTP \(code)")
            }
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle?.write(contentsOf: data)
            received += Int64(data.count)
            onData(data, false)
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        if let failure = failure ?? error {
            continuation?.resume(throwing: failure)
        } else {
            continuation?.resume(returning: received)
        }
        continuation = nil
    }
}
