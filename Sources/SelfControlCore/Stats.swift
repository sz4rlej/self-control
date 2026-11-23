import Foundation

/// Próby wejścia na zablokowane strony.
public struct Stats: Codable, Equatable {
    public struct Attempt: Codable, Equatable {
        public var domain: String
        public var at: Date
        public init(domain: String, at: Date) { self.domain = domain; self.at = at }
    }

    /// Ile minut skupienia kosztuje jedno rozproszenie.
    public static let focusMinutesPerAttempt = 3
    /// Żądania tej samej domeny w tym czasie to jedna próba (przekierowania, podwójne żądania przeglądarki).
    public static let dedupeWindow: TimeInterval = 5
    static let keepDays = 60

    public var attempts: [Attempt]

    public init(attempts: [Attempt] = []) { self.attempts = attempts }

    /// Zapisuje próbę; zwraca false, jeśli to powtórka w oknie deduplikacji.
    @discardableResult
    public mutating func record(domain: String, at now: Date) -> Bool {
        if let last = attempts.last(where: { $0.domain == domain }), now.timeIntervalSince(last.at) < Self.dedupeWindow {
            return false
        }
        attempts.append(Attempt(domain: domain, at: now))
        let cutoff = now.addingTimeInterval(-Double(Self.keepDays) * 86400)
        attempts.removeAll { $0.at < cutoff }
        return true
    }

    public struct Summary: Equatable {
        public var domainToday = 0, domainWeek = 0, allToday = 0, allWeek = 0
        public var savedTodayMinutes: Int { allToday * Stats.focusMinutesPerAttempt }
        public var savedWeekMinutes: Int { allWeek * Stats.focusMinutesPerAttempt }
    }

    public func summary(domain: String? = nil, now: Date, calendar: Calendar = .current) -> Summary {
        var iso = calendar
        iso.firstWeekday = 2 // tydzień od poniedziałku
        let dayStart = iso.startOfDay(for: now)
        let weekStart = iso.dateInterval(of: .weekOfYear, for: now)?.start ?? dayStart
        var s = Summary()
        for a in attempts where a.at >= weekStart && a.at <= now {
            let today = a.at >= dayStart
            s.allWeek += 1
            if today { s.allToday += 1 }
            if a.domain == domain {
                s.domainWeek += 1
                if today { s.domainToday += 1 }
            }
        }
        return s
    }

    /// Domena z listy, do której należy host (np. "old.reddit.com" -> "reddit.com").
    public static func matchDomain(host: String, in domains: [String]) -> String? {
        var h = host.lowercased()
        if let i = h.firstIndex(of: ":") { h = String(h[..<i]) }
        return domains.filter { h == $0 || h.hasSuffix("." + $0) }.max { $0.count < $1.count }
    }
}

public func formatMinutes(_ m: Int) -> String {
    m < 60 ? "\(m) min" : (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min")
}

public enum BlockPage {
    public static func render(domain: String, summary s: Stats.Summary, until: Date?, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = calendar.isDateInToday(until ?? Date()) ? "HH:mm" : "EEEE, HH:mm"
        let untilText = until.map { "Blokada trwa do \(f.string(from: $0))." } ?? ""
        let d = escape(domain)

        return """
        <!doctype html>
        <html lang="pl"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(d) — zablokowane</title>
        <style>
        :root { --bg:#f5f5f7; --card:#fff; --fg:#1d1d1f; --muted:#6e6e73; --line:#e5e5ea; --accent:#ff3b30; --good:#34c759; }
        @media (prefers-color-scheme: dark) { :root { --bg:#1c1c1e; --card:#2c2c2e; --fg:#f5f5f7; --muted:#98989d; --line:#3a3a3c; --accent:#ff453a; --good:#30d158; } }
        * { box-sizing:border-box; }
        body { margin:0; min-height:100vh; display:grid; place-items:center; background:var(--bg); color:var(--fg);
               font:15px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; padding:24px; }
        main { width:100%; max-width:460px; text-align:center; }
        .lock { width:56px; height:56px; border-radius:14px; background:var(--accent); display:grid; place-items:center; margin:0 auto 18px; }
        h1 { font-size:22px; font-weight:600; margin:0 0 4px; }
        .sub { color:var(--muted); margin:0 0 28px; }
        .big { font-size:64px; font-weight:200; line-height:1; letter-spacing:-1px; }
        .big small { display:block; font-size:14px; font-weight:400; color:var(--muted); letter-spacing:0; margin-top:8px; }
        .card { background:var(--card); border:0.5px solid var(--line); border-radius:12px; margin-top:28px; text-align:left; }
        .row { display:flex; justify-content:space-between; padding:11px 14px; }
        .row + .row { border-top:0.5px solid var(--line); }
        .row span:last-child { font-variant-numeric:tabular-nums; color:var(--muted); }
        .saved span:last-child { color:var(--good); font-weight:600; }
        .note { color:var(--muted); font-size:12px; margin-top:14px; }
        </style></head>
        <body><main>
        <div class="lock"><svg width="24" height="28" viewBox="0 0 24 28" fill="none"><rect x="2" y="12" width="20" height="15" rx="3" fill="#fff"/><path d="M6.5 12V8a5.5 5.5 0 0 1 11 0v4" stroke="#fff" stroke-width="3"/></svg></div>
        <h1>\(d) jest zablokowane</h1>
        <p class="sub">\(untilText) Wracaj do roboty.</p>
        <div class="big">\(s.domainToday).<small>próba wejścia tutaj dzisiaj · \(s.domainWeek) w tym tygodniu</small></div>
        <div class="card">
          <div class="row"><span>Wszystkie próby dziś</span><span>\(s.allToday)</span></div>
          <div class="row"><span>Wszystkie próby w tym tygodniu</span><span>\(s.allWeek)</span></div>
          <div class="row saved"><span>Odzyskany czas dziś</span><span>\(formatMinutes(s.savedTodayMinutes))</span></div>
          <div class="row saved"><span>Odzyskany czas w tym tygodniu</span><span>\(formatMinutes(s.savedWeekMinutes))</span></div>
        </div>
        <p class="note">Liczymy ok. \(Stats.focusMinutesPerAttempt) min utraconego skupienia na każde rozproszenie.</p>
        </main></body></html>
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
