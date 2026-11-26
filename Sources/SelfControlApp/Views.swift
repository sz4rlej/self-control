import SwiftUI
import SelfControlCore

@main
struct SelfControlApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Snapshot.runIfRequested(model: _model.wrappedValue)
    }

    var body: some Scene {
        MenuBarExtra {
            RootView().environmentObject(model)
        } label: {
            Image(nsImage: menuBarIcon(model.blocking))
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Pomocnicze

func durationLabel(_ m: Int) -> String {
    m < 60 ? "\(m) min" : (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min")
}

enum Tab: String, CaseIterable {
    case status, domains, schedule
    var title: String { ["status": "Blokada", "domains": "Domeny", "schedule": "Harmonogram"][rawValue]! }
}

/// Zaokrąglona grupa w stylu Ustawień systemowych.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

struct GroupRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack { content }
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: Tab

    init(initialTab: Tab = .status) { _tab = State(initialValue: initialTab) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case .status: StatusView()
                case .domains: DomainsView()
                case .schedule: ScheduleListView()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if !model.daemonAlive {
                Label("Demon nie działa — uruchom scripts/install.sh", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let e = model.error {
                Label(e, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(width: 320, height: 470)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.blocking ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(model.blocking ? Color.red : Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 0) {
                Text("Self-Control").font(.headline)
                Text(model.blocking ? "Blokada aktywna" : "Brak blokady")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Toggle("Uruchamiaj przy logowaniu", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                Divider()
                Button("Zakończ Self-Control") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

// MARK: - Blokada

struct StatusView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("duration") private var minutes = 60
    @AppStorage("pomodoroMode") private var pomodoroMode = false
    @AppStorage("breakMinutes") private var breakMinutes = 15

    private let presets = [15, 30, 60, 120, 240]
    private let pomodoroPresets = [(25, 5), (45, 15), (50, 10)]

    /// Wybór w menu „Czas”: "60" albo "p45/15".
    private var choice: Binding<String> {
        Binding(
            get: { pomodoroMode ? "p\(minutes)/\(breakMinutes)" : "\(minutes)" },
            set: { v in
                if v.hasPrefix("p") {
                    let parts = v.dropFirst().split(separator: "/").compactMap { Int($0) }
                    minutes = parts[0]; breakMinutes = parts[1]; pomodoroMode = true
                } else {
                    minutes = Int(v) ?? 60; pomodoroMode = false
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            Dial().frame(maxWidth: .infinity).padding(.vertical, 4)

            SettingsGroup {
                GroupRow {
                    Text("Czas")
                    Spacer()
                    Picker("", selection: choice) {
                        ForEach(presets, id: \.self) { Text(durationLabel($0)).tag("\($0)") }
                        if !pomodoroMode, !presets.contains(minutes) { Text(durationLabel(minutes)).tag("\(minutes)") }
                        Divider()
                        ForEach(pomodoroPresets, id: \.0) { w, b in Text("Pomodoro \(w)/\(b)").tag("p\(w)/\(b)") }
                        if pomodoroMode, !pomodoroPresets.contains(where: { $0 == (minutes, breakMinutes) }) {
                            Text("Pomodoro \(minutes)/\(breakMinutes)").tag("p\(minutes)/\(breakMinutes)")
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider().padding(.leading, 10)
                if pomodoroMode {
                    GroupRow {
                        Text("Praca")
                        Text("\(minutes)").monospacedDigit().foregroundStyle(.secondary)
                        Stepper("", value: $minutes, in: 5...240, step: 5).labelsHidden()
                        Spacer()
                        Text("Przerwa")
                        Text("\(breakMinutes)").monospacedDigit().foregroundStyle(.secondary)
                        Stepper("", value: $breakMinutes, in: 5...60, step: 5).labelsHidden()
                    }
                } else {
                    GroupRow {
                        Text("Dokładnie")
                        Spacer()
                        Text(durationLabel(minutes)).monospacedDigit().foregroundStyle(.secondary)
                        Stepper("", value: $minutes, in: 5...(24 * 60), step: 5).labelsHidden()
                    }
                }
            }

            mainButton

            let s = model.stats.summary(now: model.now)
            if s.allWeek > 0 {
                SettingsGroup {
                    GroupRow {
                        Text("Próby wejścia")
                        Spacer()
                        Text("dziś \(s.allToday) · tydzień \(s.allWeek)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Divider().padding(.leading, 10)
                    GroupRow {
                        Text("Odzyskany czas")
                        Spacer()
                        Text("\(formatMinutes(s.savedTodayMinutes)) · \(formatMinutes(s.savedWeekMinutes))")
                            .monospacedDigit().foregroundStyle(.green)
                    }
                }
            }

            if let p = model.pomodoro {
                HStack(spacing: 6) {
                    Text("Pomodoro \(p.work)/\(p.rest) · sesja \(p.session)")
                    Button("Zakończ cykl") { model.stopPomodoro() }
                        .buttonStyle(.link)
                }
                .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Raz włączonej blokady nie da się przerwać.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var mainButton: some View {
        if let p = model.pomodoro, p.phase == .rest {
            Button { model.startPomodoro(work: p.work, rest: p.rest) } label: {
                Text("Kolejna sesja \(p.work) min teraz").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
        } else if pomodoroMode && !model.blocking && model.pomodoro == nil {
            Button { model.startPomodoro(work: minutes, rest: breakMinutes) } label: {
                Text("Start pomodoro \(minutes)/\(breakMinutes)").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        } else {
            Button { model.block(for: minutes) } label: {
                Text(model.blocking ? "Przedłuż o \(durationLabel(minutes))" : "Zablokuj na \(durationLabel(minutes))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(model.blocking ? .red : .accentColor)
            .keyboardShortcut(.defaultAction)
        }
    }
}

struct Dial: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            ZStack {
                Circle().stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 8)
                if model.blocking, let until = model.blockingUntil {
                    Circle()
                        .trim(from: 0, to: progress(now: now, until: until))
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(countdown(now: now, until: until))
                            .font(.system(size: 30, weight: .light))
                            .monospacedDigit()
                        Text(sessionPrefix + "do \(until.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let p = model.pomodoro, p.phase == .rest {
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.02, min(1, p.until.timeIntervalSince(now) / Double(p.rest * 60)))))
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(countdown(now: now, until: p.until))
                            .font(.system(size: 30, weight: .light))
                            .monospacedDigit()
                        Text("Przerwa · do \(p.until.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.green)
                    }
                } else {
                    VStack(spacing: 4) {
                        Text("Wolne").font(.system(size: 26, weight: .light))
                        Text(nextText(now: now))
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 18)
                }
            }
            .frame(width: 140, height: 140)
        }
    }

    private var sessionPrefix: String {
        guard let p = model.pomodoro, p.phase == .work else { return "" }
        return "Sesja \(p.session) · "
    }

    private func progress(now: Date, until: Date) -> CGFloat {
        let start = model.blockingStart ?? now
        let total = until.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return CGFloat(max(0.02, min(1, until.timeIntervalSince(now) / total)))
    }

    private func countdown(now: Date, until: Date) -> String {
        let s = max(0, Int(until.timeIntervalSince(now)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func nextText(now: Date) -> String {
        guard let next = model.nextScheduled else { return "Brak zaplanowanych" }
        let cal = Calendar.current
        let d = next.date
        let time = d.formatted(date: .omitted, time: .shortened)
        let day: String
        if cal.isDate(d, inSameDayAs: now) { day = "dziś" }
        else if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { day = "jutro" }
        else { day = Weekday.shortNames[Weekday.iso(of: d)]! }
        return "\(next.name): \(day) \(time)"
    }
}

// MARK: - Domeny

struct DomainsView: View {
    @EnvironmentObject var model: AppModel
    @State private var input = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("np. youtube.com", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .onChange(of: input) { invalid = false }
                Button("Dodaj", action: add).disabled(input.isEmpty)
                Menu {
                    ForEach(Preset.all) { p in
                        Button("\(p.name) (\(p.domains.count))") { model.addDomains(p.domains) }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Gotowe listy")
            }
            if invalid { Text("Niepoprawna domena").font(.caption).foregroundStyle(.red) }

            let domains = model.config.normalizedDomains
            if domains.isEmpty {
                Text("Brak domen.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ScrollView {
                    SettingsGroup {
                        ForEach(Array(domains.enumerated()), id: \.element) { i, d in
                            if i > 0 { Divider().padding(.leading, 10) }
                            GroupRow {
                                Text(d)
                                Spacer()
                                if model.lockedDomains.contains(d) {
                                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                                        .help("Usunięcie zadziała po końcu blokady")
                                }
                                Button { model.removeDomain(d) } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

            }

            Text(verbatim: model.blocking && model.pendingChanges
                 ? "Usunięcia zadziałają po końcu blokady."
                 : "Blokowane są też warianty www., m. i mobile.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func add() {
        guard !input.isEmpty else { return }
        invalid = !model.addDomain(input)
        if !invalid { input = "" }
    }
}

// MARK: - Harmonogram

struct ScheduleListView: View {
    @EnvironmentObject var model: AppModel
    /// Edytujemy kopię; demon dostaje ją dopiero po „Zapisz”.
    @State private var draft: [Schedule] = []

    private var dirty: Bool { draft != model.config.schedules }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if draft.isEmpty {
                Text("Brak harmonogramów.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($draft) { $s in
                            ScheduleCard(schedule: $s, locked: model.isScheduleLocked(s), enforced: model.enforcedSchedule(s.id)) {
                                draft.removeAll { $0.id == s.id }
                            }
                        }
                    }
                }

            }

            if dirty, let until = model.extendsBlock(with: draft) {
                Label("Zapis od razu włączy blokadę do \(until.formatted(date: .omitted, time: .shortened)) i nie da się jej cofnąć.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Button {
                    draft.append(Schedule(name: "Nowy", days: [1, 2, 3, 4, 5], startMinute: 9 * 60, endMinute: 12 * 60, enabled: false))
                } label: { Label("Dodaj", systemImage: "plus") }
                Spacer()
                if dirty {
                    Button("Cofnij") { draft = model.config.schedules }
                    Button("Zapisz") { model.config.schedules = draft }
                        .buttonStyle(.borderedProminent)
                        .tint(model.extendsBlock(with: draft) != nil ? .red : .accentColor)
                } else if model.blocking && model.pendingChanges {
                    Text("Zmiany po końcu blokady").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { draft = model.config.schedules }
        .onChange(of: model.config.schedules) { _, new in draft = new }
    }
}

struct ScheduleCard: View {
    @Binding var schedule: Schedule
    let locked: Bool
    /// Wersja, którą demon wymusza do końca trwającego okna.
    var enforced: Schedule? = nil
    let onDelete: () -> Void

    var body: some View {
        SettingsGroup {
            GroupRow {
                TextField("Nazwa", text: $schedule.name)
                    .textFieldStyle(.plain)
                    .fontWeight(.medium)
                if locked {
                    Text("trwa").font(.caption).foregroundStyle(.red)
                }
                Toggle("", isOn: $schedule.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Divider().padding(.leading, 10)
            GroupRow {
                HStack(spacing: 3) {
                    ForEach(Weekday.all, id: \.self) { d in
                        Toggle(Weekday.shortNames[d]!, isOn: Binding(
                            get: { schedule.days.contains(d) },
                            set: { if $0 { schedule.days.insert(d) } else { schedule.days.remove(d) } }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.vertical, 4)
            Divider().padding(.leading, 10)
            GroupRow {
                Text("Od").foregroundStyle(.secondary)
                TimeField(minutes: $schedule.startMinute)
                Text("do").foregroundStyle(.secondary)
                TimeField(minutes: $schedule.endMinute)
                if schedule.endMinute <= schedule.startMinute {
                    Text("+1 dzień").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Usuń harmonogram")
            }
            .padding(.vertical, 2)
            if locked, let e = enforced, e != schedule {
                Divider().padding(.leading, 10)
                GroupRow {
                    Label("Teraz obowiązuje \(hm(e.startMinute))–\(hm(e.endMinute)); zmiany po końcu tego okna.",
                          systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.red)
                }
                .padding(.vertical, 4)
            }
        }
        .opacity(schedule.enabled ? 1 : 0.6)
    }
}

struct TimeField: View {
    @Binding var minutes: Int

    var body: some View {
        DatePicker("", selection: Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes * 60)) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
        .datePickerStyle(.stepperField)
        .fixedSize()
    }
}

func hm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

private func menuBarIcon(_ blocking: Bool) -> NSImage {
    let name = blocking ? "hand.raised.fill" : "hand.raised"
    let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
    let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) ?? NSImage()
    img.isTemplate = true
    return img
}
