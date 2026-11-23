import Foundation

/// Dni tygodnia w formacie ISO: 1 = poniedziałek … 7 = niedziela.
public enum Weekday {
    public static let all: [Int] = Array(1...7)
    public static let shortNames = [1: "Pn", 2: "Wt", 3: "Śr", 4: "Cz", 5: "Pt", 6: "So", 7: "Nd"]

    public static func iso(of date: Date, calendar: Calendar = .current) -> Int {
        let w = calendar.component(.weekday, from: date) // 1 = niedziela
        return (w + 5) % 7 + 1
    }
}

public struct Schedule: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var days: Set<Int>
    /// Minuty od północy. Jeśli `endMinute <= startMinute`, okno przechodzi przez północ.
    public var startMinute: Int
    public var endMinute: Int
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, days: Set<Int>, startMinute: Int, endMinute: Int, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.days = days
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.enabled = enabled
    }

    var spansMidnight: Bool { endMinute <= startMinute }

    /// Koniec okna, jeśli harmonogram jest aktywny w chwili `date`; w przeciwnym razie nil.
    public func activeUntil(_ date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, !days.isEmpty else { return nil }
        let day = Weekday.iso(of: date, calendar: calendar)
        let yesterday = day == 1 ? 7 : day - 1
        let startOfDay = calendar.startOfDay(for: date)
        let minute = Int(date.timeIntervalSince(startOfDay) / 60)

        func at(_ minutes: Int, dayOffset: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay)!
            return calendar.date(byAdding: .minute, value: minutes, to: base)!
        }

        if spansMidnight {
            if days.contains(day), minute >= startMinute { return at(endMinute, dayOffset: 1) }
            if days.contains(yesterday), minute < endMinute { return at(endMinute, dayOffset: 0) }
            return nil
        }
        if days.contains(day), minute >= startMinute, minute < endMinute { return at(endMinute, dayOffset: 0) }
        return nil
    }

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        activeUntil(date, calendar: calendar) != nil
    }

    /// Najbliższy początek okna po `date` (w ciągu 8 dni).
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, !days.isEmpty else { return nil }
        let startOfDay = calendar.startOfDay(for: date)
        for offset in 0...7 {
            let day = calendar.date(byAdding: .day, value: offset, to: startOfDay)!
            guard days.contains(Weekday.iso(of: day, calendar: calendar)) else { continue }
            let start = calendar.date(byAdding: .minute, value: startMinute, to: day)!
            if start > date { return start }
        }
        return nil
    }
}

public struct Config: Codable, Equatable {
    public var domains: [String]
    public var schedules: [Schedule]
    /// Koniec ręcznie uruchomionej blokady.
    public var manualUntil: Date?

    public init(domains: [String] = [], schedules: [Schedule] = [], manualUntil: Date? = nil) {
        self.domains = domains
        self.schedules = schedules
        self.manualUntil = manualUntil
    }

    public static let starter = Config(
        domains: ["facebook.com", "instagram.com", "youtube.com", "x.com", "reddit.com"],
        schedules: [Schedule(name: "Praca", days: [1, 2, 3, 4, 5], startMinute: 9 * 60, endMinute: 17 * 60, enabled: false)]
    )

    /// Do kiedy trwa blokada (najpóźniejszy koniec z aktywnych źródeł), albo nil.
    /// Kolejne, stykające się okna harmonogramów są sklejane.
    public func blockingUntil(at date: Date, calendar: Calendar = .current) -> Date? {
        var until: Date? = nil
        var cursor = date
        // Sklejamy okna, które zaczynają się dokładnie tam, gdzie kończy się poprzednie.
        for _ in 0..<14 {
            var next: Date? = nil
            if let m = manualUntil, m > cursor { next = m }
            for s in schedules {
                if let end = s.activeUntil(cursor, calendar: calendar), end > (next ?? .distantPast) { next = end }
            }
            guard let n = next, n > cursor else { break }
            until = n
            cursor = n
        }
        return until
    }

    public func isBlocking(at date: Date, calendar: Calendar = .current) -> Bool {
        blockingUntil(at: date, calendar: calendar) != nil
    }

    public var normalizedDomains: [String] {
        var seen = Set<String>()
        return domains.compactMap(Domain.normalize).filter { seen.insert($0).inserted }
    }
}

/// Stan zapisywany przez demona (tylko do odczytu dla aplikacji).
public struct DaemonState: Codable, Equatable {
    public var effective: Config
    public var blocking: Bool
    public var blockingUntil: Date?
    public var updatedAt: Date

    public init(effective: Config, blocking: Bool, blockingUntil: Date?, updatedAt: Date) {
        self.effective = effective
        self.blocking = blocking
        self.blockingUntil = blockingUntil
        self.updatedAt = updatedAt
    }
}

public enum Domain {
    /// "https://www.Facebook.com/foo" -> "facebook.com"
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let i = s.firstIndex(where: { "/?#:".contains($0) }) { s = String(s[..<i]) }
        while s.hasPrefix("www.") { s.removeFirst(4) }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard s.contains("."), s.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return s
    }

    /// Warianty hosta wpisywane do /etc/hosts.
    public static func hostVariants(_ domain: String) -> [String] {
        [domain, "www.\(domain)", "m.\(domain)", "mobile.\(domain)"]
    }
}

public enum Policy {
    /// Łączy konfigurację żądaną przez użytkownika z obowiązującą.
    /// Podczas blokady można ją tylko zaostrzać: domen nie da się usunąć,
    /// blokady ręcznej skrócić, a aktywnego harmonogramu wyłączyć ani zmienić.
    /// Takie zmiany wchodzą w życie po końcu blokady.
    public static func merge(effective: Config, requested: Config, now: Date, calendar: Calendar = .current) -> Config {
        var result = requested
        result.domains = requested.normalizedDomains
        guard effective.isBlocking(at: now, calendar: calendar) else { return result }

        for d in effective.normalizedDomains where !result.domains.contains(d) {
            result.domains.append(d)
        }
        if let m = effective.manualUntil, m > now {
            result.manualUntil = max(m, requested.manualUntil ?? m)
        }
        for s in effective.schedules where s.isActive(at: now, calendar: calendar) {
            if let i = result.schedules.firstIndex(where: { $0.id == s.id }) {
                result.schedules[i] = s
            } else {
                result.schedules.append(s)
            }
        }
        return result
    }
}

public enum Paths {
    private static let env = ProcessInfo.processInfo.environment
    public static var request: URL {
        URL(fileURLWithPath: env["SELFCONTROL_REQUEST"] ?? "/Users/Shared/SelfControl/request.json")
    }
    public static var state: URL {
        URL(fileURLWithPath: env["SELFCONTROL_STATE"] ?? "/Library/Application Support/SelfControl/state.json")
    }
    public static var hosts: URL {
        URL(fileURLWithPath: env["SELFCONTROL_HOSTS"] ?? "/etc/hosts")
    }
}

public enum JSON {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
