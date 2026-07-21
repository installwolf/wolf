import Foundation
import BulwarkCore

// bulwarkd — the root watchdog. On a loop it:
//   1. loads state,
//   2. drains any removals whose cooldown has elapsed,
//   3. re-applies every enforcement layer (self-heals tampering),
//   4. advances a monotonic clock floor to defeat clock-rollback.
// launchd (KeepAlive) restarts it if it's killed.

nonisolated(unsafe) let store = Store()
let tick: TimeInterval = 15

func log(_ msg: String) {
    FileHandle.standardError.write(Data("[bulwarkd] \(msg)\n".utf8))
}

/// Monotonic clock floor: persisted "latest time we've ever seen". Using
/// max(system clock, floor) means winding the clock *back* to postpone... or
/// rather to escape a floored state is defeated. Forward jumps remain a
/// documented residual hole (see DESIGN.md) — the real fix is a signed remote clock.
func effectiveNow() -> Date {
    let system = Date()
    let floorPath = Paths.clockFloorFile
    var floor = system
    if let raw = try? String(contentsOfFile: floorPath, encoding: .utf8),
       let t = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
        floor = Date(timeIntervalSince1970: t)
    }
    let now = max(system, floor)
    // Persist the new floor.
    Enforcer.setImmutable(false, path: floorPath)
    try? String(now.timeIntervalSince1970).write(toFile: floorPath, atomically: true, encoding: .utf8)
    Enforcer.setImmutable(true, path: floorPath)
    return now
}

func cycle() {
    do {
        var state = try store.load()
        let now = effectiveNow()
        let drained = state.drainDue(now: now)
        if !drained.isEmpty {
            try store.save(state)
            log("cooldown elapsed, unblocked: \(drained.joined(separator: ", "))")
        }
        try Enforcer.apply(state)
    } catch {
        log("cycle error: \(error)")
    }
}

guard geteuid() == 0 else {
    log("must run as root")
    exit(1)
}

log("started (tick \(Int(tick))s)")
while true {
    cycle()
    Thread.sleep(forTimeInterval: tick)
}
