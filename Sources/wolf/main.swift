import Foundation
import WolfCore

// wolf — the control CLI. Everyday commands (add/remove/cancel/enable) go to the
// root daemon over a local socket, so they need no sudo; the daemon enforces the
// removal gate. Sensitive setup and `panic` stay root-gated (deliberate friction).

signal(SIGPIPE, SIG_IGN)

nonisolated(unsafe) let store = Store()
let args = Array(CommandLine.arguments.dropFirst())

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + msg + "\n").utf8))
    exit(1)
}

func requireRoot() {
    // Root protects the real system files; a sandbox (WOLF_HOSTS set) has nothing to protect.
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

/// Send a mutating command to the daemon (no sudo). Fall back to a direct,
/// privileged call only if we're already root/sandbox; otherwise explain.
func dispatch(_ req: CommandRequest) -> Never {
    if let res = SocketIPC.clientSend(req) {
        res.lines.forEach { print($0) }
        exit(res.ok ? 0 : 1)
    }
    let sandbox = ProcessInfo.processInfo.environment["WOLF_HOSTS"] != nil
    if geteuid() == 0 || sandbox {
        let res = CommandProcessor.handle(req, store: store, now: Date())
        res.lines.forEach { print($0) }
        exit(res.ok ? 0 : 1)
    }
    fail("can't reach the Wolf daemon (is wolfd running?). Fallback: sudo wolf \(args.joined(separator: " "))")
}

// MARK: - Commands

func cmdStatus() {
    let s = loadState()
    if !s.enabled {
        print("Wolf — ⏸ DISABLED (kill switch). \(s.blocked.count) site(s) saved but not enforced. `wolf enable` to resume.")
    }
    print("Wolf — \(s.blocked.count) site(s) blocked, cooldown \(humanDuration(s.config.cooldownSeconds)), partner passphrase \(s.config.passphrase == nil ? "NOT set" : "set"), \(s.config.protectedDomains.count) custom-protected.")
    if s.blocked.isEmpty {
        print("  (nothing blocked yet — `wolf add <site>`)")
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

// --- everyday commands: via daemon, no sudo ---

func cmdAdd(_ sites: [String]) {
    guard !sites.isEmpty else { fail("usage: wolf add <site> [site...]") }
    dispatch(CommandRequest(cmd: "add", args: sites))
}

func cmdRemove(_ argv: [String]) {
    let instant = argv.contains("--now")
    let positional = argv.filter { !$0.hasPrefix("--") }
    guard let site = positional.first else { fail("usage: wolf remove <site> [--now]") }
    var req = CommandRequest(cmd: "remove", args: instant ? [site, "--now"] : [site])
    if instant { req.passphrase = promptSecret("Partner passphrase: ") }
    dispatch(req)
}

func cmdCancel(_ sites: [String]) {
    guard let site = sites.first else { fail("usage: wolf cancel <site>") }
    dispatch(CommandRequest(cmd: "cancel", args: [site]))
}

func cmdEnable() {
    dispatch(CommandRequest(cmd: "enable", args: []))
}

// --- setup / sensitive commands: root-gated (deliberate friction) ---

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
    Audit.record("protect: \(prot.joined(separator: ", "))", notifying: s.config)
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
    Audit.record("unprotect: \(d)", notifying: s.config)
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
    Audit.record("disable (clean, passphrase)", notifying: s.config)
    print("Wolf disabled. Blocklist kept. Re-enable with: wolf enable")
}

func cmdPanic(_ argv: [String]) {
    requireRoot()
    let preconfirmed = argv.contains("--confirm") || argv.contains("--yes")
    func teardown(_ tag: String) {
        let s = (try? store.load()) ?? WolfState()
        Audit.record("PANIC scorched-earth\(tag) — wiped \(s.blocked.count) blocked site(s); passphrase was \(s.config.passphrase == nil ? "absent" : "SET")", notifying: s.config)
        try? Enforcer.clearAll()
        Shell.run("/bin/launchctl", ["bootout", "system", Paths.daemonPlist])
        Enforcer.setImmutable(false, path: Paths.stateFile)
        Enforcer.setImmutable(false, path: Paths.clockFloorFile)
        try? FileManager.default.removeItem(atPath: Paths.stateFile)
        try? FileManager.default.removeItem(atPath: Paths.clockFloorFile)
    }
    if preconfirmed {
        teardown(" (--confirm)")
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
    teardown("")
    print("\nWolf is fully disabled and its config wiped. Your Mac is unrestricted.")
    print("To start over later: sudo wolf bootstrap")
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
    Audit.record("partner passphrase set/changed", notifying: s.config)
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
        guard let pp = s.config.passphrase else {
            fail("shortening the cooldown requires a partner passphrase (none set). You may only increase it.")
        }
        let pass = promptSecret("Partner passphrase (required to shorten cooldown): ")
        guard Passphrase.verify(pass, against: pp) else { fail("passphrase incorrect.") }
    }
    let old = s.config.cooldownSeconds
    s.config.cooldownSeconds = new
    persistAndEnforce(s)
    Audit.record("cooldown \(humanDuration(old)) → \(humanDuration(new))", notifying: s.config)
    print("cooldown set to \(humanDuration(new)).")
}

func cmdEnforce() {
    requireRoot()
    let s = loadState()
    do { try Enforcer.apply(s) } catch { fail("\(error)") }
    print("enforcement re-applied.")
}

/// One-time privileged setup, run once after `brew install`: copy the watchdog
/// binary to a root-owned path, wire the pf anchor into pf.conf, install and
/// start the LaunchDaemon. `install.sh` does the same for source installs; this
/// is the Homebrew path (`brew install` runs unprivileged, so this is the single
/// `sudo` step). Idempotent — safe to re-run.
func cmdBootstrap(_ argv: [String]) {
    requireRoot()

    // 1. Locate the freshly-installed wolfd (sibling of this binary, or --wolfd).
    func resolveWolfd() -> String? {
        if let i = argv.firstIndex(of: "--wolfd"), i + 1 < argv.count { return argv[i + 1] }
        guard let exe = Bundle.main.executablePath else { return nil }
        let real = (exe as NSString).resolvingSymlinksInPath
        let sibling = (real as NSString).deletingLastPathComponent + "/wolfd"
        return FileManager.default.isExecutableFile(atPath: sibling) ? sibling : nil
    }
    guard let src = resolveWolfd() else {
        fail("could not find the wolfd binary next to wolf — pass it with: sudo wolf bootstrap --wolfd <path>")
    }

    print("==> Installing watchdog to a root-owned path")
    Enforcer.setImmutable(false, path: Paths.daemonBin)                 // in case of re-run
    Shell.run("/bin/launchctl", ["bootout", "system", Paths.daemonPlist]) // stop it holding the old binary
    try? FileManager.default.createDirectory(
        atPath: (Paths.daemonBin as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    let cp = Shell.run("/usr/bin/install", ["-m", "755", src, Paths.daemonBin])
    guard cp.status == 0 else { fail("copying wolfd failed: \(cp.err)") }

    print("==> Creating state directory")
    try? FileManager.default.createDirectory(atPath: Paths.home, withIntermediateDirectories: true)

    print("==> Wiring the pf anchor (so blocks survive reboot)")
    if !FileManager.default.fileExists(atPath: Paths.pfAnchor) {
        try? FileManager.default.createDirectory(
            atPath: (Paths.pfAnchor as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? "# managed by wolf\n".write(toFile: Paths.pfAnchor, atomically: true, encoding: .utf8)
    }
    let pfConf = (try? String(contentsOfFile: Paths.pfConf, encoding: .utf8)) ?? ""
    if let wired = PfConf.wire(into: pfConf, anchorPath: Paths.pfAnchor) {
        try? pfConf.write(toFile: Paths.pfConf + ".wolf-backup", atomically: true, encoding: .utf8)
        do { try wired.write(toFile: Paths.pfConf, atomically: true, encoding: .utf8) }
        catch { fail("could not write \(Paths.pfConf): \(error)") }
    }

    print("==> Installing and starting the watchdog daemon")
    let plist = DaemonPlist.render(wolfdPath: Paths.daemonBin)
    do { try plist.write(toFile: Paths.daemonPlist, atomically: true, encoding: .utf8) }
    catch { fail("could not write \(Paths.daemonPlist): \(error)") }
    Shell.run("/bin/launchctl", ["bootstrap", "system", Paths.daemonPlist])
    Shell.run("/bin/launchctl", ["enable", "system/\(DaemonPlist.label)"])

    print("""

    Wolf is bootstrapped and the watchdog is running. Next:
      1. Have your accountability partner set the passphrase (don't watch):
           sudo wolf set-passphrase
      2. Block sites (no sudo — the daemon handles it):
           wolf add pornhub.com xvideos.com
      3. Check status any time:
           wolf status
    """)
}

func usage() {
    print("""
    wolf — self-binding website blocker

    Everyday (no sudo — handled by the wolfd daemon):
      wolf status                 show blocked sites and any pending removals
      wolf add <site>...          block site(s) immediately (unresolvable domains
                                  are refused as typos; add --force to override)
      wolf remove <site>          queue removal after the cooldown
      wolf remove <site> --now    remove now (needs partner passphrase)
      wolf cancel <site>          cancel a pending removal (re-commit)
      wolf enable                 resume enforcement after a disable

    Setup & safety (need sudo — deliberate friction):
      sudo wolf set-passphrase    set/change the partner passphrase
      sudo wolf set-cooldown <h>  increase freely; shortening needs passphrase
      sudo wolf protect <domain>...   never allow this domain to be blocked
      sudo wolf unprotect <domain>    remove a custom protection
      sudo wolf disable           clean shutdown (needs partner passphrase)
      sudo wolf panic             BREAK-GLASS: wipe everything, always works
      sudo wolf enforce           force re-apply enforcement now
      sudo wolf bootstrap         one-time setup after `brew install`
    """)
}

// MARK: - Dispatch

switch args.first {
case "status", nil:      cmdStatus()
case "add":              cmdAdd(Array(args.dropFirst()))
case "remove", "rm":     cmdRemove(Array(args.dropFirst()))
case "cancel":           cmdCancel(Array(args.dropFirst()))
case "enable":           cmdEnable()
case "set-passphrase":   cmdSetPassphrase()
case "set-cooldown":     cmdSetCooldown(Array(args.dropFirst()))
case "protect":          cmdProtect(Array(args.dropFirst()))
case "unprotect":        cmdUnprotect(Array(args.dropFirst()))
case "disable":          cmdDisable()
case "panic":            cmdPanic(Array(args.dropFirst()))
case "enforce":          cmdEnforce()
case "bootstrap":        cmdBootstrap(Array(args.dropFirst()))
case "help", "-h", "--help": usage()
default:
    FileHandle.standardError.write(Data("unknown command: \(args[0])\n\n".utf8))
    usage()
    exit(1)
}
