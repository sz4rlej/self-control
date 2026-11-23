import Foundation

public enum Hosts {
    public static let beginMarker = "# >>> self-control (nie edytuj) >>>"
    public static let endMarker = "# <<< self-control <<<"
    /// Adresy pętli zwrotnej, na których demon pokazuje stronę blokady
    /// (osobne aliasy, żeby nie gryźć się z lokalnymi serwerami na 127.0.0.1).
    public static let blockIPv4 = "127.94.0.1"
    public static let blockIPv6 = "fd5c:5c5c::1"

    /// Zwraca treść pliku hosts bez sekcji self-control, z nową sekcją dla `domains` (pusta = brak sekcji).
    public static func render(original: String, domains: [String]) -> String {
        var lines: [String] = []
        var inside = false
        for line in original.components(separatedBy: "\n") {
            if line == beginMarker { inside = true; continue }
            if line == endMarker { inside = false; continue }
            if !inside { lines.append(line) }
        }
        while let last = lines.last, last.isEmpty { lines.removeLast() }

        if !domains.isEmpty {
            lines.append("")
            lines.append(beginMarker)
            for d in domains {
                for h in Domain.hostVariants(d) {
                    lines.append("\(blockIPv4)\t\(h)")
                    lines.append("\(blockIPv6)\t\(h)")
                }
            }
            lines.append(endMarker)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
