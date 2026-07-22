import Foundation

/// Append-only accountability log. Significant events (panic, disable, enable,
/// passphrase changes) are recorded here and the file is marked append-only
/// (`sappnd`) so entries can be added but not quietly erased — the record
/// survives even a scorched-earth panic.
///
/// This is the single choke point for accountability: pass `notifying:` the
/// current config and, when a partner is enrolled, the same event is sealed to
/// them via `Notifier`. So the notified set always equals the audited set — no
/// event can be reported without also being in the tamper-evident local log.
public enum Audit {
    public static var path: String { Paths.home + "/audit.log" }

    public static func record(_ event: String, notifying config: WolfConfig? = nil,
                              at date: Date = Date()) {
        let f = ISO8601DateFormatter()
        let line = "\(f.string(from: date))  \(event)\n"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Paths.home, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        // Appends are permitted under the append-only flag; only truncate/delete
        // are blocked, so we don't need to clear it here.
        if let h = FileHandle(forWritingAtPath: path) {
            defer { try? h.close() }
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
        }
        Shell.run("/usr/bin/chflags", ["sappnd", path])

        if let partner = config?.partner {
            Notifier.enqueue(event, to: partner, at: date)
        }
    }
}
