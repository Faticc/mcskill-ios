import Foundation

public enum Format {
    /** The API sends the wipe date as epoch seconds in a string; "—" when there is none. */
    public static func wipeDate(_ raw: String, timeZone: TimeZone = .current) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let seconds = Int64(text) else { return text.isEmpty ? "—" : text }
        if seconds <= 0 { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    /** "1 мод", "3 мода", "11 модов". */
    public static func mods(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        let word: String
        if mod10 == 1 && mod100 != 11 {
            word = "мод"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            word = "мода"
        } else {
            word = "модов"
        }
        return "\(n) \(word)"
    }
}
