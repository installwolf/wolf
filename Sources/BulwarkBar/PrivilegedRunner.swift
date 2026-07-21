import Foundation

/// Runs the `bulwark` CLI. Read-only status comes straight from the state file
/// (no privilege needed); mutating actions are run through the macOS
/// authorization dialog via `osascript … with administrator privileges`.
enum PrivilegedRunner {
    static let cli = "/usr/local/bin/bulwark"

    enum RunError: Error, LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let m) = self { return m }; return nil }
    }

    /// Run a mutating subcommand as root. `args` must already be sanitized
    /// (domains canonicalized, verbs fixed) — we build a plain space-joined
    /// command, so never pass untrusted free-form strings.
    @discardableResult
    static func runAdmin(_ args: [String]) throws -> String {
        let shellCmd = ([cli] + args).joined(separator: " ")
        let script = "do shell script \"\(shellCmd)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let outStr = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errStr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            // User cancelling the auth dialog shows up as an osascript error too.
            throw RunError.failed(errStr.isEmpty ? "cancelled or failed" : errStr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return outStr
    }
}
