import Foundation

public enum Hosts {
    public static let beginMarker = "# >>> self-control (nie edytuj) >>>"
    public static let endMarker = "# <<< self-control <<<"

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
                    lines.append("0.0.0.0\t\(h)")
                    lines.append("::\t\(h)")
                }
            }
            lines.append(endMarker)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
