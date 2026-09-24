import Foundation

/**
 * The app's own log, Documents/logs/launcher.log: visible in the Files app and sent with
 * "Поделиться логами" - on a friend's iPhone there is no adb to read it otherwise.
 */
public enum AppLog {
    private static let queue = DispatchQueue(label: "ru.hts.log")
    private static let maxSize = 2 * 1024 * 1024

    public static let fileURL: URL = {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("logs", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("launcher.log")
        // One previous file is kept, launcher.1.log
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxSize {
            let old = dir.appendingPathComponent("launcher.1.log")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        return url
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    public static func info(_ message: String) {
        write("I", message)
    }

    public static func error(_ message: String) {
        write("E", message)
    }

    private static func write(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) \(level) \(message)\n"
        print(line, terminator: "")
        queue.async {
            guard let data = line.data(using: .utf8),
                  let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
