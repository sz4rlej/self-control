import Foundation
import ServiceManagement
import SelfControlCore

@MainActor
final class AppModel: ObservableObject {
    /// Konfiguracja edytowana przez użytkownika (zapisywana jako żądanie dla demona).
    @Published var config: Config {
        didSet { if config != oldValue { save() } }
    }
    @Published private(set) var state: DaemonState?
    @Published private(set) var now = Date()
    @Published private(set) var stats = Stats()
    @Published var error: String?

    private var timer: Timer?

    init() {
        let state = JSON.load(DaemonState.self, from: Paths.state)
        self.state = state
        self.config = JSON.load(Config.self, from: Paths.request) ?? state?.effective ?? .starter
        if !FileManager.default.fileExists(atPath: Paths.request.path) { save() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        now = Date()
        state = JSON.load(DaemonState.self, from: Paths.state)
        stats = JSON.load(Stats.self, from: Paths.stats) ?? Stats()
        trackBlockStart()
    }

    private func save() {
        do {
            try JSON.save(config, to: Paths.request)
            error = nil
        } catch {
            self.error = "Nie mogę zapisać ustawień: \(error.localizedDescription)"
        }
    }

    // MARK: - Stan

    var daemonAlive: Bool {
        guard let s = state else { return false }
        return now.timeIntervalSince(s.updatedAt) < 30
    }

    var blocking: Bool { state?.blocking ?? false }
    var blockingUntil: Date? { state?.blockingUntil }

    /// Początek bieżącej blokady (do paska postępu) — zapamiętywany przy pierwszym zauważeniu.
    var blockingStart: Date? {
        UserDefaults.standard.object(forKey: "blockStart") as? Date
    }

    private func trackBlockStart() {
        let d = UserDefaults.standard
        if blocking {
            if d.object(forKey: "blockStart") == nil { d.set(now, forKey: "blockStart") }
        } else {
            d.removeObject(forKey: "blockStart")
        }
    }

    /// Najbliższa zaplanowana blokada i jej nazwa.
    var nextScheduled: (date: Date, name: String)? {
        config.schedules
            .compactMap { s in s.nextStart(after: now).map { ($0, s.name) } }
            .min { $0.0 < $1.0 }
            .map { (date: $0.0, name: $0.1) }
    }

    /// Czy dana domena jest obecnie wymuszana przez demona mimo usunięcia.
    var lockedDomains: Set<String> {
        guard blocking, let eff = state?.effective else { return [] }
        return Set(eff.normalizedDomains)
    }

    func isScheduleLocked(_ s: Schedule) -> Bool {
        guard blocking, let eff = state?.effective.schedules.first(where: { $0.id == s.id }) else { return false }
        return eff.isActive(at: now)
    }

    func enforcedSchedule(_ id: UUID) -> Schedule? {
        state?.effective.schedules.first { $0.id == id }
    }

    var pendingChanges: Bool {
        guard let eff = state?.effective else { return false }
        return Set(config.normalizedDomains) != Set(eff.normalizedDomains) || config.schedules != eff.schedules
    }

    // MARK: - Akcje

    func block(for minutes: Int) {
        let target = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let current = max(config.manualUntil ?? .distantPast, state?.effective.manualUntil ?? .distantPast)
        config.manualUntil = max(target, current)
    }

    func addDomain(_ raw: String) -> Bool {
        guard let d = Domain.normalize(raw) else { return false }
        if !config.normalizedDomains.contains(d) { config.domains.append(d) }
        return true
    }

    func addDomains(_ list: [String]) {
        for d in list { _ = addDomain(d) }
    }

    func removeDomain(_ d: String) {
        config.domains.removeAll { Domain.normalize($0) == d }
    }

    func addSchedule() {
        config.schedules.append(Schedule(name: "Nowy", days: [1, 2, 3, 4, 5], startMinute: 9 * 60, endMinute: 12 * 60))
    }

    func removeSchedule(_ id: UUID) {
        config.schedules.removeAll { $0.id == id }
    }

    /// Do kiedy trwałaby blokada po zapisaniu tych harmonogramów — jeśli dłużej niż obecnie.
    func extendsBlock(with schedules: [Schedule]) -> Date? {
        var c = state?.effective ?? config
        c.schedules = schedules
        guard let until = c.blockingUntil(at: Date()) else { return nil }
        return until > (blockingUntil ?? Date()) ? until : nil
    }

    // MARK: - Start przy logowaniu

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                self.error = "Start przy logowaniu: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }
}
