import Foundation

/// Renders and splices Bulwark's managed section into `/etc/hosts`.
/// The section is delimited by markers so we can replace it idempotently
/// without disturbing the user's own entries.
public enum HostsRenderer {
    public static let beginMarker = "# >>> BULWARK MANAGED BLOCK — do not edit, changes are reverted >>>"
    public static let endMarker = "# <<< BULWARK MANAGED BLOCK <<<"

    /// The managed section (markers included) for the given domains.
    public static func managedBlock(_ domains: [String]) -> String {
        var lines = [beginMarker]
        for d in domains.sorted() {
            lines.append("0.0.0.0 \(d)")
            lines.append("0.0.0.0 www.\(d)")
        }
        lines.append(endMarker)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Returns `existing` with the managed section replaced (or appended if absent).
    public static func splice(into existing: String, domains: [String]) -> String {
        let block = managedBlock(domains)
        guard let start = existing.range(of: beginMarker),
              let end = existing.range(of: endMarker) else {
            var base = existing
            if !base.hasSuffix("\n") && !base.isEmpty { base += "\n" }
            return base + block
        }
        // Extend the end range to include the trailing newline if present.
        var endIdx = end.upperBound
        if endIdx < existing.endIndex, existing[endIdx] == "\n" {
            endIdx = existing.index(after: endIdx)
        }
        var result = existing
        result.replaceSubrange(start.lowerBound..<endIdx, with: block)
        return result
    }
}
