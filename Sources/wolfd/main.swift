import Foundation
import WolfCore

// wolfd — the root watchdog. On a loop it:
//   1. loads state, 2. drains removals whose cooldown elapsed, 3. re-applies
//   enforcement (self-heals tampering), 4. advances a monotonic clock floor.
// It also serves a local socket so the unprivileged `wolf` CLI can issue
// commands without sudo; the removal gate is still enforced here (as root).
// launchd (KeepAlive) restarts it if it's killed.

signal(SIGPIPE, SIG_IGN)   // never die because a CLI client hung up mid-write

nonisolated(unsafe) let store = Store()
let stateLock = NSLock()   // serializes tick vs. IPC requests
let tick: TimeInterval = 15

func log(_ msg: String) {
    FileHandle.standardError.write(Data("[wolfd] \(msg)\n".utf8))
}

/// Monotonic clock floor: max(system clock, persisted floor), so winding the
/// clock back to escape a cooldown is defeated. Forward jumps remain a
/// documented residual hole (see DESIGN.md).
func effectiveNow() -> Date {
    let floorPath = Paths.clockFloorFile
    let system = Date()
    var floor = system
    if let raw = try? String(contentsOfFile: floorPath, encoding: .utf8),
       let t = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
        floor = Date(timeIntervalSince1970: t)
    }
    let now = max(system, floor)
    Enforcer.setImmutable(false, path: floorPath)
    try? String(now.timeIntervalSince1970).write(toFile: floorPath, atomically: true, encoding: .utf8)
    Enforcer.setImmutable(true, path: floorPath)
    return now
}

func cycle() {
    stateLock.lock()
    defer { stateLock.unlock() }
    do {
        var state = try store.load()
        let drained = state.drainDue(now: effectiveNow())
        if !drained.isEmpty {
            try store.save(state)
            log("cooldown elapsed, unblocked: \(drained.joined(separator: ", "))")
        }
        try Enforcer.apply(state)
    } catch {
        log("cycle error: \(error)")
    }
}

let sandbox = ProcessInfo.processInfo.environment["WOLF_HOSTS"] != nil
guard geteuid() == 0 || sandbox else {
    log("must run as root")
    exit(1)
}

// Serve the CLI socket on a background thread (removal gate enforced in-process).
Thread.detachNewThread {
    SocketIPC.serve(store: store, lock: stateLock,
                    now: { effectiveNow() },
                    log: { log($0) })
}

log("started (tick \(Int(tick))s)\(sandbox ? " [sandbox]" : "")")
while true {
    cycle()
    Thread.sleep(forTimeInterval: tick)
}
