import Foundation
import Security
import SelfControlCore

/// Lokalny urząd certyfikacji i certyfikat dla zablokowanych domen,
/// żeby przeglądarka pokazała stronę blokady zamiast błędu HTTPS.
/// Klucze leżą w katalogu demona z prawami 600 (tylko root).
final class Certs {
    static let caName = "Self-Control Local CA"
    private let dir: URL
    private let p12Pass = "selfcontrol"
    private let lock = NSLock()
    private var identity: SecIdentity?
    private var domainsKey = ""

    init(dir: URL) { self.dir = dir.appendingPathComponent("tls") }

    var caCert: URL { dir.appendingPathComponent("ca.crt") }
    private var caKey: URL { dir.appendingPathComponent("ca.key") }
    private var leafKey: URL { dir.appendingPathComponent("leaf.key") }
    private var leafCrt: URL { dir.appendingPathComponent("leaf.crt") }
    private var leafP12: URL { dir.appendingPathComponent("leaf.p12") }
    private var leafDomains: URL { dir.appendingPathComponent("leaf.domains") }

    var currentIdentity: SecIdentity? { lock.withLock { identity } }

    func ensureCA() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard !FileManager.default.fileExists(atPath: caKey.path) else { return }
        openssl(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256",
                 "-keyout", caKey.path, "-out", caCert.path, "-days", "3650",
                 "-subj", "/CN=\(Self.caName)",
                 "-addext", "basicConstraints=critical,CA:TRUE",
                 "-addext", "keyUsage=critical,keyCertSign,cRLSign"])
        chmod(caKey.path, 0o600)
        chmod(caCert.path, 0o644)
        log("utworzono lokalny CA")
    }

    /// Generuje certyfikat, jeśli zmieniła się lista domen albo zbliża się koniec ważności.
    func update(domains: [String]) {
        let key = domains.sorted().joined(separator: ",")
        if key == domainsKey, identity != nil { return }
        guard !domains.isEmpty else { return }

        let saved = (try? String(contentsOf: leafDomains, encoding: .utf8)) ?? ""
        let age = (try? FileManager.default.attributesOfItem(atPath: leafP12.path)[.modificationDate] as? Date).flatMap { $0 }
        let fresh = age.map { Date().timeIntervalSince($0) < 300 * 86400 } ?? false
        if saved != key || !fresh || !FileManager.default.fileExists(atPath: leafP12.path) {
            generateLeaf(domains: domains)
            try? key.write(to: leafDomains, atomically: true, encoding: .utf8)
        }
        if let id = loadIdentity() {
            lock.withLock { identity = id; domainsKey = key }
        }
    }

    private func generateLeaf(domains: [String]) {
        if !FileManager.default.fileExists(atPath: leafKey.path) {
            openssl(["genrsa", "-out", leafKey.path, "2048"])
            chmod(leafKey.path, 0o600)
        }
        let csr = dir.appendingPathComponent("leaf.csr")
        let ext = dir.appendingPathComponent("leaf.ext")
        let sans = domains.flatMap { ["DNS:\($0)", "DNS:*.\($0)"] }.joined(separator: ",")
        try? """
        subjectAltName=\(sans)
        extendedKeyUsage=serverAuth
        basicConstraints=CA:FALSE
        keyUsage=critical,digitalSignature,keyEncipherment
        """.write(to: ext, atomically: true, encoding: .utf8)
        openssl(["req", "-new", "-key", leafKey.path, "-out", csr.path, "-subj", "/CN=Self-Control"])
        openssl(["x509", "-req", "-in", csr.path, "-CA", caCert.path, "-CAkey", caKey.path,
                 "-set_serial", String(Int(Date().timeIntervalSince1970)), "-sha256",
                 "-days", "397", "-out", leafCrt.path, "-extfile", ext.path])
        openssl(["pkcs12", "-export", "-inkey", leafKey.path, "-in", leafCrt.path,
                 "-out", leafP12.path, "-passout", "pass:\(p12Pass)"])
        chmod(leafP12.path, 0o600)
        log("certyfikat dla \(domains.count) domen")
    }

    private func loadIdentity() -> SecIdentity? {
        guard let data = try? Data(contentsOf: leafP12) else { return nil }
        var items: CFArray?
        let opts: [String: Any] = [kSecImportExportPassphrase as String: p12Pass, kSecImportToMemoryOnly as String: true]
        guard SecPKCS12Import(data as CFData, opts as CFDictionary, &items) == errSecSuccess,
              let first = (items as? [[String: Any]])?.first,
              let id = first[kSecImportItemIdentity as String] else {
            log("nie mogę wczytać certyfikatu")
            return nil
        }
        return (id as! SecIdentity)
    }

    private func openssl(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { log("openssl \(args.first ?? "") zakończył się błędem \(p.terminationStatus)") }
    }
}
