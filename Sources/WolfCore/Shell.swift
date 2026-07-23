import Foundation

/// Thin wrapper over Process for the handful of privileged system commands
/// enforcement needs (chflags, pfctl, launchctl).
public enum Shell {
    @discardableResult
    public static func run(_ path: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        // Darwin's Pipe does not close the read ends on deinit here, so without
        // this every call leaks two fds. The daemon runs Shell.run several times
        // per tick, so the leak exhausts the process fd limit within minutes and
        // then every daemon operation fails with EMFILE ("Too many open files").
        defer {
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()
        }
        do { try p.run() } catch {
            return (-1, "", "failed to launch \(path): \(error)")
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(decoding: outData, as: UTF8.self),
                String(decoding: errData, as: UTF8.self))
    }
}
