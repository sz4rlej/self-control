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

    public struct DomainCount: Equatable {
        public var domain: String
        public var count: Int
    }

    public struct Summary: Equatable {
        public var domainToday = 0, domainWeek = 0, allToday = 0, allWeek = 0
        /// Domeny wg liczby prób dziś (malejąco).
        public var topToday: [DomainCount] = []
        /// Liczba prób dziś w każdej godzinie (0…23).
        public var hourlyToday = Array(repeating: 0, count: 24)
        /// Dzisiejsze próby, najnowsze pierwsze.
        public var recentToday: [Attempt] = []
        public var savedTodayMinutes: Int { allToday * Stats.focusMinutesPerAttempt }
        public var savedWeekMinutes: Int { allWeek * Stats.focusMinutesPerAttempt }
    }

    public func summary(domain: String? = nil, now: Date, calendar: Calendar = .current) -> Summary {
        var iso = calendar
        iso.firstWeekday = 2 // tydzień od poniedziałku
        let dayStart = iso.startOfDay(for: now)
        let weekStart = iso.dateInterval(of: .weekOfYear, for: now)?.start ?? dayStart
        var s = Summary()
        var perDomain: [String: Int] = [:]
        for a in attempts where a.at >= weekStart && a.at <= now {
            let today = a.at >= dayStart
            s.allWeek += 1
            if today {
                s.allToday += 1
                perDomain[a.domain, default: 0] += 1
                s.hourlyToday[iso.component(.hour, from: a.at)] += 1
                s.recentToday.append(a)
            }
            if a.domain == domain {
                s.domainWeek += 1
                if today { s.domainToday += 1 }
            }
        }
        s.topToday = perDomain.map { DomainCount(domain: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.domain < $1.domain }
        s.recentToday.reverse()
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
        .card { background:var(--card); border:0.5px solid var(--line); border-radius:12px; margin-top:28px; text-align:left; overflow:hidden; }
        .row { display:flex; justify-content:space-between; padding:11px 14px; }
        .row + .row { border-top:0.5px solid var(--line); }
        .row span:last-child { font-variant-numeric:tabular-nums; color:var(--muted); }
        .saved span:last-child { color:var(--good); font-weight:600; }
        .note { color:var(--muted); font-size:12px; margin-top:14px; }
        h2 { font-size:13px; font-weight:600; color:var(--muted); text-transform:uppercase; letter-spacing:.4px; text-align:left; margin:28px 4px 8px; }
        h2 + .card { margin-top:0; }
        .bar { position:relative; }
        .bar::before { content:""; position:absolute; left:0; top:0; bottom:0; width:var(--w); background:var(--accent); opacity:.1; }
        .bar.me::before { opacity:.2; }
        .bar span { position:relative; }
        .hours { display:flex; align-items:flex-end; gap:3px; height:96px; padding:14px 14px 0; }
        .hours div { flex:1; display:flex; flex-direction:column; justify-content:flex-end; align-items:center; height:100%; }
        .hours i { display:block; width:100%; background:var(--accent); border-radius:3px 3px 0 0; min-height:0; }
        .hours i.zero { background:var(--line); height:2px !important; }
        .hours b { font-size:10px; font-weight:500; color:var(--muted); margin-bottom:2px; font-variant-numeric:tabular-nums; }
        .labels { display:flex; gap:3px; padding:4px 14px 10px; }
        .labels span { flex:1; text-align:center; font-size:10px; color:var(--muted); font-variant-numeric:tabular-nums; }
        .time { color:var(--muted); font-variant-numeric:tabular-nums; margin-right:10px; }
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
        \(details(domain: domain, summary: s, calendar: calendar))
        <p class="note">Liczymy ok. \(Stats.focusMinutesPerAttempt) min utraconego skupienia na każde rozproszenie.</p>
        </main></body></html>
        """
    }

    /// Ranking domen, rozkład godzinowy i lista dzisiejszych prób.
    static func details(domain: String, summary s: Stats.Summary, calendar: Calendar) -> String {
        guard !s.topToday.isEmpty else { return "" }
        var html = ""

        let maxCount = s.topToday.first?.count ?? 1
        let rows = s.topToday.prefix(8).map { item -> String in
            let w = Int((Double(item.count) / Double(maxCount) * 100).rounded())
            let me = item.domain == domain ? " me" : ""
            return "<div class=\"row bar\(me)\" style=\"--w:\(w)%\"><span>\(escape(item.domain))</span><span>\(item.count)</span></div>"
        }
        html += "<h2>Najczęściej dziś</h2><div class=\"card\">\(rows.joined())</div>"

        // Godziny od pierwszej próby (najpóźniej od 8) do bieżącej / ostatniej.
        let active = s.hourlyToday.indices.filter { s.hourlyToday[$0] > 0 }
        let nowHour = calendar.component(.hour, from: Date())
        let from = min(active.first ?? 8, 8)
        let to = max(active.last ?? nowHour, min(nowHour, 23), from + 7)
        let range = from...min(to, 23)
        let peak = max(range.map { s.hourlyToday[$0] }.max() ?? 1, 1)
        let bars = range.map { h -> String in
            let n = s.hourlyToday[h]
            let pct = Int(Double(n) / Double(peak) * 100)
            return n == 0 ? "<div><i class=\"zero\"></i></div>"
                : "<div><b>\(n)</b><i style=\"height:\(max(pct, 4))%\"></i></div>"
        }
        let labels = range.map { "<span>\($0)</span>" }
        html += "<h2>O której godzinie</h2><div class=\"card\"><div class=\"hours\">\(bars.joined())</div><div class=\"labels\">\(labels.joined())</div></div>"

        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "HH:mm"
        let recent = s.recentToday.prefix(10).map {
            "<div class=\"row\"><span><span class=\"time\">\(f.string(from: $0.at))</span>\(escape($0.domain))</span><span></span></div>"
        }
        let more = s.recentToday.count > 10 ? "<div class=\"row\"><span class=\"time\">…i \(s.recentToday.count - 10) wcześniej</span><span></span></div>" : ""
        html += "<h2>Ostatnie próby</h2><div class=\"card\">\(recent.joined())\(more)</div>"
        return html
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
