import XCTest
@testable import SelfControlCore

final class CoreTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    // 2026-11-23 to poniedziałek.
    func date(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    func testWeekday() {
        XCTAssertEqual(Weekday.iso(of: date(23, 12), calendar: cal), 1)
        XCTAssertEqual(Weekday.iso(of: date(29, 12), calendar: cal), 7)
    }

    func testScheduleWindow() {
        let s = Schedule(name: "Praca", days: [1, 2, 3, 4, 5], startMinute: 9 * 60, endMinute: 17 * 60)
        XCTAssertFalse(s.isActive(at: date(23, 8, 59), calendar: cal))
        XCTAssertEqual(s.activeUntil(date(23, 9), calendar: cal), date(23, 17))
        XCTAssertFalse(s.isActive(at: date(23, 17), calendar: cal))
        XCTAssertFalse(s.isActive(at: date(28, 10), calendar: cal)) // sobota
    }

    func testOvernight() {
        let s = Schedule(name: "Noc", days: [7], startMinute: 22 * 60, endMinute: 6 * 60)
        XCTAssertEqual(s.activeUntil(date(29, 23), calendar: cal), date(30, 6)) // nd 23:00
        XCTAssertEqual(s.activeUntil(date(23, 5), calendar: cal), date(23, 6))  // pn 5:00 (z niedzieli)
        XCTAssertFalse(s.isActive(at: date(24, 5), calendar: cal))
    }

    func testChainedWindows() {
        let a = Schedule(name: "A", days: [1], startMinute: 9 * 60, endMinute: 12 * 60)
        let b = Schedule(name: "B", days: [1], startMinute: 12 * 60, endMinute: 14 * 60)
        let c = Config(domains: ["x.com"], schedules: [a, b])
        XCTAssertEqual(c.blockingUntil(at: date(23, 10), calendar: cal), date(23, 14))
    }

    func testNormalize() {
        XCTAssertEqual(Domain.normalize("https://www.Facebook.com/foo?x=1"), "facebook.com")
        XCTAssertEqual(Domain.normalize(" youtube.com:443 "), "youtube.com")
        XCTAssertNil(Domain.normalize("localhost"))
        XCTAssertNil(Domain.normalize("zła domena.pl"))
    }

    func testMergeCannotWeakenDuringBlock() {
        let now = date(23, 10)
        let work = Schedule(name: "Praca", days: [1], startMinute: 9 * 60, endMinute: 17 * 60)
        let effective = Config(domains: ["a.com", "b.com"], schedules: [work], manualUntil: date(23, 18))
        var disabled = work; disabled.enabled = false
        let requested = Config(domains: ["a.com", "c.com"], schedules: [disabled], manualUntil: date(23, 11))

        let m = Policy.merge(effective: effective, requested: requested, now: now, calendar: cal)
        XCTAssertEqual(Set(m.domains), ["a.com", "b.com", "c.com"])
        XCTAssertEqual(m.manualUntil, date(23, 18))
        XCTAssertTrue(m.schedules[0].enabled)
    }

    func testMergeFreeWhenNotBlocking() {
        let effective = Config(domains: ["a.com"], manualUntil: date(23, 9))
        let requested = Config(domains: [])
        let m = Policy.merge(effective: effective, requested: requested, now: date(23, 10), calendar: cal)
        XCTAssertEqual(m, requested)
    }

    func testHostsRenderIsIdempotent() {
        let base = "127.0.0.1\tlocalhost\n"
        let blocked = Hosts.render(original: base, domains: ["x.com"])
        XCTAssertTrue(blocked.contains("127.94.0.1\twww.x.com"))
        XCTAssertEqual(Hosts.render(original: blocked, domains: ["x.com"]), blocked)
        XCTAssertEqual(Hosts.render(original: blocked, domains: []), base)
    }

    func testStats() {
        var st = Stats()
        XCTAssertTrue(st.record(domain: "x.com", at: date(23, 10)))
        XCTAssertFalse(st.record(domain: "x.com", at: date(23, 10, 0).addingTimeInterval(3)))
        st.record(domain: "x.com", at: date(23, 11))
        st.record(domain: "y.com", at: date(23, 11))
        st.record(domain: "x.com", at: date(22, 11)) // niedziela — poprzedni tydzień
        let s = st.summary(domain: "x.com", now: date(23, 12), calendar: cal)
        XCTAssertEqual(s.domainToday, 2)
        XCTAssertEqual(s.domainWeek, 2)
        XCTAssertEqual(s.allToday, 3)
        XCTAssertEqual(s.savedTodayMinutes, 9)
        XCTAssertEqual(Stats.matchDomain(host: "old.reddit.com:443", in: ["reddit.com", "x.com"]), "reddit.com")
        XCTAssertNil(Stats.matchDomain(host: "notreddit.com", in: ["reddit.com"]))
    }
}
