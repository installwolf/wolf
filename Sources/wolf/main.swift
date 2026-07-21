import Foundation
import WolfCore

// wolf — the control CLI. Adding is instant; removing is gated by a
// cooldown or the accountability-partner passphrase. Mutating commands need root.

nonisolated(unsafe) let store = Store()
let args = Array(CommandLine.arguments.dropFirst())

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + msg + "\n").utf8))
    exit(1)
}

func requireRoot() {
    // Root is required only to protect the real system files. When paths are
    // redirected to a sandbox (WOLF_HOSTS set), there's nothing to protect.
    if ProcessInfo.processInfo.environment["WOLF_HOSTS"] != nil { return }
    guard geteuid() == 0 else {
        fail("this command changes protected system state — re-run with: sudo wolf \(args.joined(separator: " "))")
    }
}

func promptSecret(_ prompt: String) -> String {
    guard let c = getpass(prompt) else { return "" }
    return String(cString: c)
}

func promptLine(_ prompt: String) -> String {
    FileHandle.standardOutput.write(Data(prompt.utf8))
    return readLine() ?? ""
}

func loadState() -> WolfState {
    do { return try store.load() } catch { fail("could not read state: \(error)") }
}

func persistAndEnforce(_ state: WolfState) {
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
    if !s.enabled {
        print("Wolf — ⏸ DISABLED (kill switch). \(s.blocked.count) site(s) saved but not enforced. `sudo wolf enable` to resume.")
    }
    print("Wolf — \(s.blocked.count) site(s) blocked, cooldown \(humanDuration(s.config.cooldownSeconds)), partner passphrase \(s.config.passphrase == nil ? "NOT set" : "set"), \(s.config.protectedDomains.count) custom-protected.")
    if s.blocked.isEmpty {
        print("  (nothing blocked yet — `sudo wolf add <site>`)")
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
    guard !sites.isEmpty else { fail("usage: sudo wolf add <site> [site...]") }
    var s = loadState()
    var added: [String] = []
    for site in sites {
        switch s.add(site) {
        case .added(let d):           added.append(d)
        case .alreadyBlocked(let d):  print("already blocked: \(d)")
        case .invalid(let raw):       print("skipped invalid: \(raw)")
        case .protectedDomain(let d): print("refused — \(d) is protected and can never be blocked (safety allowlist)")
        }
    }
    guard !added.isEmpty else { print("nothing added."); return }
    persistAndEnforce(s)
    Audit.record("add: \(added.joined(separator: ", "))")
    print("blocked (effective immediately): \(added.joined(separator: ", "))")
}

func cmdProtect(_ sites: [String]) {
    requireRoot()
    guard !sites.isEmpty else { fail("usage: sudo wolf protect <domain>...") }
    var s = loadState()
    var prot: [String] = []
    for site in sites {
        guard let d = Domain.canonical(site) else { print("skipped invalid: \(site)"); continue }
        s.config.protectedDomains.insert(d)
        prot.append(d)
    }
    guard !prot.isEmpty else { return }
    persistAndEnforce(s)
    Audit.record("protect: \(prot.joined(separator: ", "))")
    print("protected — can never be blocked: \(prot.joined(separator: ", "))")
    print("(protecting does not unblock anything already blocked)")
}

func cmdUnprotect(_ sites: [String]) {
    requireRoot()
    guard let site = sites.first, let d = Domain.canonical(site) else {
        fail("usage: sudo wolf unprotect <domain>")
    }
    if Allowlist.critical.contains(d) {
        fail("\(d) is a built-in critical protection and cannot be unprotected.")
    }
    var s = loadState()
    guard s.config.protectedDomains.remove(d) != nil else { fail("\(d) was not in your protected list.") }
    persistAndEnforce(s)
    Audit.record("unprotect: \(d)")
    print("removed protection for \(d).")
}

func cmdDisable() {
    requireRoot()
    var s = loadState()
    guard s.config.passphrase != nil else {
        fail("clean disable needs a partner passphrase. For a genuine emergency use `sudo wolf panic`.")
    }
    let pass = promptSecret("Partner passphrase to disable Wolf: ")
    guard s.disable(passphrase: pass) else { fail("passphrase incorrect — still enabled.") }
    persistAndEnforce(s)
    Audit.record("disable (clean, passphrase)")
    print("Wolf disabled. Blocklist kept. Re-enable with: sudo wolf enable")
}

func cmdEnable() {
    requireRoot()
    var s = loadState()
    s.enable()
    persistAndEnforce(s)
    Audit.record("enable")
    print("Wolf re-enabled — \(s.blocked.count) site(s) enforced.")
}

func cmdPanic(_ argv: [String]) {
    requireRoot()
    let preconfirmed = argv.contains("--confirm") || argv.contains("--yes")
    if preconfirmed {
        let s = (try? store.load()) ?? WolfState()
        Audit.record("PANIC scorched-earth (--confirm) — wiped \(s.blocked.count) blocked site(s); passphrase was \(s.config.passphrase == nil ? "absent" : "SET")")
        try? Enforcer.clearAll()
        Shell.run("/bin/launchctl", ["bootout", "system", Paths.daemonPlist])
        Enforcer.setImmutable(false, path: Paths.stateFile)
        Enforcer.setImmutable(false, path: Paths.clockFloorFile)
        try? FileManager.default.removeItem(atPath: Paths.stateFile)
        try? FileManager.default.removeItem(atPath: Paths.clockFloorFile)
        print("Wolf fully disabled and wiped.")
        return
    }
    print("""
    ⚠️  PANIC — break-glass emergency kill switch.

    This COMPLETELY DISABLES Wolf and WIPES your setup: blocklist, cooldown,
    and the partner passphrase are all destroyed. It is recorded permanently in
    the append-only audit log (\(Audit.path)).

    It exists so a malfunction can never trap you — not as a way around a craving.
    Using it means rebuilding your whole setup (and telling your partner).
    """)
    guard promptLine("\nType  DESTROY WOLF  to proceed: ") == "DESTROY WOLF" else {
        fail("aborted — nothing changed.")
    }
    let s = (try? store.load()) ?? WolfState()
    Audit.record("PANIC scorched-earth — wiped \(s.blocked.count) blocked site(s); passphrase was \(s.config.passphrase == nil ? "absent" : "SET")")
    try? Enforcer.clearAll()
    Shell.run("/bin/launchctl", ["bootout", "system", Paths.daemonPlist])
    Enforcer.setImmutable(false, path: Paths.stateFile)
    Enforcer.setImmutable(false, path: Paths.clockFloorFile)
    try? FileManager.default.removeItem(atPath: Paths.stateFile)
    try? FileManager.default.removeItem(atPath: Paths.clockFloorFile)
    print("\nWolf is fully disabled and its config wiped. Your Mac is unrestricted.")
    print("To start over later: sudo ./install/install.sh")
}

func cmdRemove(_ argv: [String]) {
    requireRoot()
    let instant = argv.contains("--now")
    let positional = argv.filter { !$0.hasPrefix("--") }
    guard let site = positional.first else { fail("usage: sudo wolf remove <site> [--now]") }
    var s = loadState()

    if instant {
        guard s.config.passphrase != nil else {
            fail("no partner passphrase is set, so instant removal is disabled. Use `sudo wolf remove \(site)` to queue it (cooldown \(humanDuration(s.config.cooldownSeconds))).")
        }
        let pass = promptSecret("Partner passphrase: ")
        if s.removeWithPassphrase(site, passphrase: pass) {
            persistAndEnforce(s)
            Audit.record("remove --now (passphrase): \(site)")
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
    Audit.record("remove queued: \(req.domain) → \(fmt(req.unlockAt))")
    print("removal queued. \(req.domain) stays blocked until \(fmt(req.unlockAt)).")
    print("changed your mind? re-committing keeps you safe: `sudo wolf add \(req.domain)`")
}

func cmdCancel(_ sites: [String]) {
    requireRoot()
    guard let site = sites.first, let d = Domain.canonical(site) else {
        fail("usage: sudo wolf cancel <site>")
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
    Audit.record("partner passphrase set/changed")
    print("partner passphrase set. Have your accountability partner set this so you never learn it.")
}

func cmdSetCooldown(_ argv: [String]) {
    requireRoot()
    guard let hoursStr = argv.first, let hours = Double(hoursStr), hours >= 0 else {
        fail("usage: sudo wolf set-cooldown <hours>")
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
    let old = s.config.cooldownSeconds
    s.config.cooldownSeconds = new
    persistAndEnforce(s)
    Audit.record("cooldown \(humanDuration(old)) → \(humanDuration(new))")
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
    wolf — self-binding website blocker

    Read-only:
      wolf status                 show blocked sites and any pending removals

    Adds are instant. Removes are gated. (need sudo)
      sudo wolf add <site>...     block site(s) immediately
      sudo wolf remove <site>     queue removal after the cooldown
      sudo wolf remove <site> --now   remove now (needs partner passphrase)
      sudo wolf cancel <site>     cancel a pending removal (re-commit)

    Safety allowlist (need sudo)
      sudo wolf protect <domain>...  never allow this domain to be blocked
      sudo wolf unprotect <domain>   remove a custom protection

    Kill switch (need sudo)
      sudo wolf disable           clean shutdown (needs partner passphrase)
      sudo wolf enable            resume enforcement
      sudo wolf panic             BREAK-GLASS: wipe everything, always works

    Setup (need sudo)
      sudo wolf set-passphrase    set/change the partner passphrase
      sudo wolf set-cooldown <h>  increase freely; shortening needs passphrase
      sudo wolf enforce           force re-apply enforcement now
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
case "protect":          cmdProtect(Array(args.dropFirst()))
case "unprotect":        cmdUnprotect(Array(args.dropFirst()))
case "disable":          cmdDisable()
case "enable":           cmdEnable()
case "panic":            cmdPanic(Array(args.dropFirst()))
case "enforce":          cmdEnforce()
case "help", "-h", "--help": usage()
default:
    FileHandle.standardError.write(Data("unknown command: \(args[0])\n\n".utf8))
    usage()
    exit(1)
}
