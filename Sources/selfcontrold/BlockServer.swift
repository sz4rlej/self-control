import Foundation
import Network
import Security
import SelfControlCore

/// Serwer HTTP/HTTPS na adresach blokady: pokazuje stronę z licznikiem prób.
final class BlockServer {
    private let queue = DispatchQueue(label: "selfcontrold.server")
    private let certs: Certs
    private var listeners: [NWListener] = []
    private var stats: Stats
    private var domains: [String] = []
    private var until: Date?

    init(certs: Certs) {
        self.certs = certs
        self.stats = JSON.load(Stats.self, from: Paths.stats) ?? Stats()
    }

    /// Aktualny stan blokady (z pętli głównej).
    func update(domains: [String], until: Date?) {
        queue.async { self.domains = domains; self.until = until }
    }

    func start() {
        // Zmienne środowiskowe tylko do testów bez roota.
        let env = ProcessInfo.processInfo.environment
        let hosts = env["SELFCONTROL_LISTEN_HOSTS"]?.split(separator: ",").map(String.init) ?? [Hosts.blockIPv4, Hosts.blockIPv6]
        let http = env["SELFCONTROL_HTTP_PORT"].flatMap(UInt16.init) ?? 80
        let https = env["SELFCONTROL_HTTPS_PORT"].flatMap(UInt16.init) ?? 443
        for host in hosts {
            listen(host: host, port: http, tls: false)
            listen(host: host, port: https, tls: true)
        }
    }

    private func listen(host: String, port: UInt16, tls: Bool) {
        let tcp = NWProtocolTCP.Options()
        let params: NWParameters
        if tls {
            let t = NWProtocolTLS.Options()
            sec_protocol_options_add_tls_application_protocol(t.securityProtocolOptions, "http/1.1")
            sec_protocol_options_set_challenge_block(t.securityProtocolOptions, { [certs] _, complete in
                complete(certs.currentIdentity.flatMap { sec_identity_create($0) })
            }, queue)
            params = NWParameters(tls: t, tcp: tcp)
        } else {
            params = NWParameters(tls: nil, tcp: tcp)
        }
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)

        do {
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] c in self?.handle(c) }
            l.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed(let e):
                    log("serwer \(host):\(port) padł: \(e) — ponawiam za 10 s")
                    l.cancel()
                    self?.queue.asyncAfter(deadline: .now() + 10) { self?.listen(host: host, port: port, tls: tls) }
                case .ready:
                    log("serwer \(host):\(port) gotowy")
                default: break
                }
            }
            l.start(queue: queue)
            listeners.append(l)
        } catch {
            log("nie mogę nasłuchiwać na \(host):\(port): \(error)")
        }
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, buffer: Data())
        queue.asyncAfter(deadline: .now() + 15) { c.cancel() }
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self)
                self.respond(c, head: head)
            } else if done || error != nil || buf.count > 65536 {
                c.cancel()
            } else {
                self.receive(c, buffer: buf)
            }
        }
    }

    private func respond(_ c: NWConnection, head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        let method = parts.first.map(String.init) ?? ""
        let path = parts.count > 1 ? String(parts[1]) : "/"
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let i = line.firstIndex(of: ":") else { continue }
            headers[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }

        let host = headers["host"] ?? ""
        guard method == "GET" || method == "HEAD", path != "/favicon.ico",
              let domain = Stats.matchDomain(host: host, in: domains) ?? Domain.normalize(host) else {
            send(c, status: "404 Not Found", body: "")
            return
        }

        // Liczymy tylko prawdziwe wejścia na stronę, nie zasoby ani prefetch.
        let isNavigation = headers["sec-fetch-dest"].map { $0 == "document" } ?? (headers["accept"]?.contains("text/html") ?? false)
        let isPrefetch = headers["sec-purpose"] != nil || headers["purpose"] != nil
        let now = Date()
        if isNavigation, !isPrefetch, until != nil, stats.record(domain: domain, at: now) {
            try? JSON.save(stats, to: Paths.stats)
            chmod(Paths.stats.path, 0o644)
        }

        guard isNavigation else {
            send(c, status: "204 No Content", body: "")
            return
        }
        let html = BlockPage.render(domain: domain, summary: stats.summary(domain: domain, now: now), until: until)
        send(c, status: "200 OK", body: method == "HEAD" ? "" : html, type: "text/html; charset=utf-8")
    }

    private func send(_ c: NWConnection, status: String, body: String, type: String = "text/plain") {
        let bytes = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(bytes.count)\r\n" +
            "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in c.cancel() })
    }
}
