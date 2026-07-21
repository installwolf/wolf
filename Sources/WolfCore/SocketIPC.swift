import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Unix-domain-socket transport between the `wolf` CLI (client) and the root
/// `wolfd` daemon (server). One request per connection, JSON both ways, framed
/// by the client shutting its write side (server reads to EOF).
public enum SocketIPC {

    private static func fillAddr(_ path: String, _ addr: inout sockaddr_un) -> Bool {
        let bytes = path.utf8CString
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count <= capacity else { return false }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                for (i, b) in bytes.enumerated() { dst[i] = b }
            }
        }
        return true
    }

    private static func readToEOF(_ fd: Int32) -> Data {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
        }
        return data
    }

    // MARK: client (CLI)

    /// Send a command to the daemon. Returns nil if the daemon isn't reachable
    /// (caller should then fall back to a direct, privileged path).
    public static func clientSend(_ req: CommandRequest) -> CommandResult? {
        guard let payload = try? JSONEncoder().encode(req) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_un()
        guard fillAddr(Paths.socket, &addr) else { return nil }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard rc == 0 else { return nil }
        _ = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        shutdown(fd, SHUT_WR)
        return try? JSONDecoder().decode(CommandResult.self, from: readToEOF(fd))
    }

    // MARK: server (daemon)

    /// Blocking accept loop. Run on a dedicated thread. Every request is handled
    /// under `lock` so it can't race the daemon's enforcement tick.
    public static func serve(store: Store, lock: NSLock,
                             now: @escaping @Sendable () -> Date,
                             log: @escaping @Sendable (String) -> Void) {
        let path = Paths.socket
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { log("ipc: socket() failed"); return }
        var addr = sockaddr_un()
        guard fillAddr(path, &addr) else { log("ipc: socket path too long"); return }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let br = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard br == 0 else { log("ipc: bind failed (\(errno))"); close(fd); return }
        chmod(path, 0o666)   // unprivileged CLI must be able to connect
        guard listen(fd, 16) == 0 else { log("ipc: listen failed"); close(fd); return }
        log("ipc: listening at \(path)")

        while true {
            let cfd = accept(fd, nil, nil)
            if cfd < 0 { continue }
            let data = readToEOF(cfd)
            let result: CommandResult
            if let req = try? JSONDecoder().decode(CommandRequest.self, from: data) {
                lock.lock()
                result = CommandProcessor.handle(req, store: store, now: now())
                lock.unlock()
                log("served \(req.cmd) -> ok=\(result.ok)")
            } else {
                result = CommandResult(ok: false, lines: ["bad request"])
            }
            if let out = try? JSONEncoder().encode(result) {
                _ = out.withUnsafeBytes { write(cfd, $0.baseAddress, $0.count) }
            }
            close(cfd)
        }
    }
}
