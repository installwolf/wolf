import Foundation

/// The App Group bridge between the host app and the sandboxed extension.
/// The host mirrors Wolf's blocklist into `blocked.txt`; the extension reads it.
enum SharedStore {
    static let appGroup = "group.com.installwolf"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
    static var blocklistURL: URL? {
        containerURL?.appendingPathComponent("blocked.txt")
    }

    /// Read blocked domains (one per line) from the shared container.
    static func readBlocklist() -> Set<String> {
        guard let url = blocklistURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }

    /// Write blocked domains to the shared container (called by the host).
    static func writeBlocklist(_ domains: Set<String>) throws {
        guard let url = blocklistURL else { return }
        try domains.sorted().joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
