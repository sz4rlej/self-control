import Foundation
import SelfControlCore

// Demon uruchamiany przez launchd jako root. Co kilka sekund:
// 1. czyta żądaną konfigurację od aplikacji,
// 2. łączy ją z obowiązującą (podczas blokady wolno tylko zaostrzać),
// 3. ustawia /etc/hosts i zapisuje stan dla aplikacji.

func log(_ msg: String) {
    FileHandle.standardError.write("[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n".data(using: .utf8)!)
}

func run(_ path: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    try? p.run()
    p.waitUntilExit()
}

func flushDNS() {
    run("/usr/bin/dscacheutil", ["-flushcache"])
    run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
}

func tick(now: Date = Date()) {
    let previous = JSON.load(DaemonState.self, from: Paths.state)
    let effective = previous?.effective ?? Config()
    let requested = JSON.load(Config.self, from: Paths.request) ?? effective

    let merged = Policy.merge(effective: effective, requested: requested, now: now)
    let until = merged.blockingUntil(at: now)
    let blocking = until != nil
    let domains = blocking ? merged.normalizedDomains : []

    // /etc/hosts — przepisujemy przy każdej różnicy, więc ręczna edycja nic nie da.
    let hostsURL = Paths.hosts
    let original = (try? String(contentsOf: hostsURL, encoding: .utf8)) ?? ""
    let updated = Hosts.render(original: original, domains: domains)
    if updated != original {
        do {
            try updated.write(to: hostsURL, atomically: true, encoding: .utf8)
            chmod(hostsURL.path, 0o644)
            flushDNS()
            log(blocking ? "blokada: \(domains.count) domen" : "blokada zdjęta")
        } catch {
            log("nie mogę zapisać \(hostsURL.path): \(error)")
        }
    }

    if previous?.blocking != blocking {
        log(blocking ? "start blokady do \(until!)" : "koniec blokady")
    }

    let state = DaemonState(effective: merged, blocking: blocking, blockingUntil: until, updatedAt: now)
    do {
        try JSON.save(state, to: Paths.state)
        chmod(Paths.state.path, 0o644)
    } catch {
        log("nie mogę zapisać stanu: \(error)")
    }
}

let once = CommandLine.arguments.contains("--once")
if !once { log("selfcontrold start") }
repeat {
    autoreleasepool { tick() }
    if !once { Thread.sleep(forTimeInterval: 5) }
} while !once
