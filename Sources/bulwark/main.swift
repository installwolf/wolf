import Foundation
import BulwarkCore

// bulwark — the control CLI. Adding is instant; removing is gated by a
// cooldown or the accountability-partner passphrase. Mutating commands need root.

nonisolated(unsafe) let store = Store()
let args = Array(CommandLine.arguments.dropFirst())

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + msg + "\n").utf8))
    exit(1)
}

func requireRoot() {
    // Root is required only to protect the real system files. When paths are
    // redirected to a sandbox (BULWARK_HOSTS set), there's nothing to protect.
    if ProcessInfo.processInfo.environment["BULWARK_HOSTS"] != nil { return }
    guard geteuid() == 0 else {
        fail("this command changes protected system state — re-run with: sudo bulwark \(args.joined(separator: " "))")
    }
}

func promptSecret(_ prompt: String) -> String {
    guard let c = getpass(prompt) else { return "" }
    return String(cString: c)
}

func loadState() -> BulwarkState {
    do { return try store.load() } catch { fail("could not read state: \(error)") }
}

func persistAndEnforce(_ state: BulwarkState) {
    do {
        try store.save(state)
        try Enforcer.apply(state)
    } catch { fail("\(error)") }
}

func fmt(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: date)
}

func humanDuration(_ seconds: TimeInterval) -> String {
    let h = Int(seconds / 3600)
    if h >= 48 { return "\(h / 24)d \(h % 24)h" }
    return "\(h)h"
}

// MARK: - Commands

func cmdStatus() {
    let s = loadState()
    print("Bulwark — \(s.blocked.count) site(s) blocked, cooldown \(humanDuration(s.config.cooldownSeconds)), partner passphrase \(s.config.passphrase == nil ? "NOT set" : "set").")
    if s.blocked.isEmpty {
        print("  (nothing blocked yet — `sudo bulwark add <site>`)")
    } else {
        for d in s.blocked.sorted() {
            let pending = s.pendingRemovals.first { $0.domain == d }
            if let p = pending {
                print("  ✗ \(d)   → unblocks \(fmt(p.unlockAt)) (removal pending)")
            } else {
                print("  ✗ \(d)")
            }
        }
    }
    let orphans = s.pendingRemovals.filter { !s.blocked.contains($0.domain) }
    if !orphans.isEmpty { print("  (\(orphans.count) stale pending removal(s))") }
}

func cmdAdd(_ sites: [String]) {
    requireRoot()
    guard !sites.isEmpty else { fail("usage: sudo bulwark add <site> [site...]") }
    var s = loadState()
    var added: [String] = []
    for site in sites {
        if let d = s.add(site) { added.append(d) } else { print("skipped invalid: \(site)") }
    }
    persistAndEnforce(s)
    print("blocked (effective immediately): \(added.joined(separator: ", "))")
}

func cmdRemove(_ argv: [String]) {
    requireRoot()
    let instant = argv.contains("--now")
    let positional = argv.filter { !$0.hasPrefix("--") }
    guard let site = positional.first else { fail("usage: sudo bulwark remove <site> [--now]") }
    var s = loadState()

    if instant {
        guard s.config.passphrase != nil else {
            fail("no partner passphrase is set, so instant removal is disabled. Use `sudo bulwark remove \(site)` to queue it (cooldown \(humanDuration(s.config.cooldownSeconds))).")
        }
        let pass = promptSecret("Partner passphrase: ")
        if s.removeWithPassphrase(site, passphrase: pass) {
            persistAndEnforce(s)
            print("removed immediately: \(site)")
        } else {
            fail("passphrase incorrect — nothing changed.")
        }
        return
    }

    guard let req = s.requestRemoval(site, now: Date()) else {
        fail("\(site) is not currently blocked (or already queued).")
    }
    persistAndEnforce(s)
    print("removal queued. \(req.domain) stays blocked until \(fmt(req.unlockAt)).")
    print("changed your mind? re-committing keeps you safe: `sudo bulwark add \(req.domain)`")
}

func cmdCancel(_ sites: [String]) {
    requireRoot()
    guard let site = sites.first, let d = Domain.canonical(site) else {
        fail("usage: sudo bulwark cancel <site>")
    }
    var s = loadState()
    let before = s.pendingRemovals.count
    s.pendingRemovals.removeAll { $0.domain == d }
    guard s.pendingRemovals.count < before else { fail("no pending removal for \(d).") }
    persistAndEnforce(s)
    print("cancelled pending removal — \(d) stays blocked.")
}

func cmdSetPassphrase() {
    requireRoot()
    var s = loadState()
    if let existing = s.config.passphrase {
        let old = promptSecret("Current partner passphrase: ")
        guard Passphrase.verify(old, against: existing) else { fail("current passphrase incorrect.") }
    }
    let new = promptSecret("New partner passphrase: ")
    let confirm = promptSecret("Confirm: ")
    guard !new.isEmpty else { fail("empty passphrase rejected.") }
    guard new == confirm else { fail("passphrases do not match.") }
    do { s.config.passphrase = try Passphrase.make(new) } catch { fail("\(error)") }
    persistAndEnforce(s)
    print("partner passphrase set. Have your accountability partner set this so you never learn it.")
}

func cmdSetCooldown(_ argv: [String]) {
    requireRoot()
    guard let hoursStr = argv.first, let hours = Double(hoursStr), hours >= 0 else {
        fail("usage: sudo bulwark set-cooldown <hours>")
    }
    var s = loadState()
    let new = hours * 3600
    if new < s.config.cooldownSeconds {
        // Shortening the cooldown weakens protection → gate behind the passphrase.
        guard let pp = s.config.passphrase else {
            fail("shortening the cooldown requires a partner passphrase (none set). You may only increase it.")
        }
        let pass = promptSecret("Partner passphrase (required to shorten cooldown): ")
        guard Passphrase.verify(pass, against: pp) else { fail("passphrase incorrect.") }
    }
    s.config.cooldownSeconds = new
    persistAndEnforce(s)
    print("cooldown set to \(humanDuration(new)).")
}

func cmdEnforce() {
    requireRoot()
    let s = loadState()
    do { try Enforcer.apply(s) } catch { fail("\(error)") }
    print("enforcement re-applied.")
}

func usage() {
    print("""
    bulwark — self-binding website blocker

    Read-only:
      bulwark status                 show blocked sites and any pending removals

    Adds are instant. Removes are gated. (need sudo)
      sudo bulwark add <site>...     block site(s) immediately
      sudo bulwark remove <site>     queue removal after the cooldown
      sudo bulwark remove <site> --now   remove now (needs partner passphrase)
      sudo bulwark cancel <site>     cancel a pending removal (re-commit)

    Setup (need sudo)
      sudo bulwark set-passphrase    set/change the partner passphrase
      sudo bulwark set-cooldown <h>  increase freely; shortening needs passphrase
      sudo bulwark enforce           force re-apply enforcement now
    """)
}

// MARK: - Dispatch

switch args.first {
case "status", nil:      cmdStatus()
case "add":              cmdAdd(Array(args.dropFirst()))
case "remove", "rm":     cmdRemove(Array(args.dropFirst()))
case "cancel":           cmdCancel(Array(args.dropFirst()))
case "set-passphrase":   cmdSetPassphrase()
case "set-cooldown":     cmdSetCooldown(Array(args.dropFirst()))
case "enforce":          cmdEnforce()
case "help", "-h", "--help": usage()
default:
    FileHandle.standardError.write(Data("unknown command: \(args[0])\n\n".utf8))
    usage()
    exit(1)
}
