import Foundation

/// Canonicalizes user-supplied site strings into a bare registrable-ish domain
/// so `https://www.Example.com/foo` and `example.com` collapse to one entry.
public enum Domain {
    public static func canonical(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }

        // Strip scheme.
        if let range = s.range(of: "://") {
            s = String(s[range.upperBound...])
        }
        // Strip everything from the first path/query/fragment separator.
        for sep in ["/", "?", "#"] {
            if let i = s.firstIndex(where: { String($0) == sep }) {
                s = String(s[..<i])
            }
        }
        // Strip userinfo (user:pass@host) and port.
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        // Drop a single leading www.
        if s.hasPrefix("www.") { s = String(s.dropFirst(4)) }

        guard isValid(s) else { return nil }
        return s
    }

    private static func isValid(_ s: String) -> Bool {
        guard s.contains("."), !s.hasPrefix("."), !s.hasSuffix(".") else { return false }
        // Labels: letters, digits, hyphens.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return s.split(separator: ".").allSatisfy { !$0.isEmpty && $0.count <= 63 }
    }
}
