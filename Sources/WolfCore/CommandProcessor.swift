import Foundation

/// A mutating command and its result, shared by the CLI and the daemon so both
/// speak the same protocol over the IPC socket. Only the low-friction everyday
/// commands go through here; sensitive setup + `panic` stay root-gated in the CLI.
public struct CommandRequest: Codable, Sendable {
    public var cmd: String
    public var args: [String]
    public var passphrase: String?
    public init(cmd: String, args: [String], passphrase: String? = nil) {
        self.cmd = cmd; self.args = args; self.passphrase = passphrase
    }
}

public struct CommandResult: Codable, Sendable {
    public var ok: Bool
    public var lines: [String]
    public init(ok: Bool, lines: [String]) { self.ok = ok; self.lines = lines }
}

/// Executes a mutating command against the store and enforcement. Must run with
/// privilege (the daemon is root; the CLI falls back to this only when itself
/// root). The removal gate lives here, so it holds no matter who calls it.
public enum CommandProcessor {
    static func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: d)
    }

    public static func handle(_ req: CommandRequest, store: Store, now: Date,
                              resolver: DomainResolver = SystemDomainResolver()) -> CommandResult {
        do {
            var state = try store.load()
            switch req.cmd {

            case "add":
                let force = req.args.contains("--force")
                let sites = req.args.filter { !$0.hasPrefix("--") }
                var added: [String] = [], lines: [String] = []
                for s in sites {
                    // Typo guard: refuse a genuinely nonexistent domain before it
                    // clutters the list. Only for new, valid, unprotected domains —
                    // already-blocked ones now sinkhole to 0.0.0.0, and protected/
                    // invalid ones are reported by `state.add` below. `--force` skips it.
                    if !force, let d = Domain.canonical(s),
                       !state.blocked.contains(d),
                       !Allowlist.isProtected(d, extra: state.config.protectedDomains),
                       resolver.check(d) == .notFound {
                        lines.append("refused — \(d) doesn't resolve (typo?). To block it anyway: wolf add \(d) --force")
                        continue
                    }
                    switch state.add(s) {
                    case .added(let d):           added.append(d)
                    case .alreadyBlocked(let d):  lines.append("already blocked: \(d)")
                    case .invalid(let raw):       lines.append("skipped invalid: \(raw)")
                    case .protectedDomain(let d): lines.append("refused — \(d) is protected and can never be blocked (safety allowlist)")
                    }
                }
                guard !added.isEmpty else { lines.append("nothing added."); return .init(ok: false, lines: lines) }
                try store.save(state); try Enforcer.apply(state)
                Audit.record("add: \(added.joined(separator: ", "))")
                lines.append("blocked (effective immediately): \(added.joined(separator: ", "))")
                return .init(ok: true, lines: lines)

            case "remove":
                let instant = req.args.contains("--now")
                guard let site = req.args.first(where: { !$0.hasPrefix("--") }) else {
                    return .init(ok: false, lines: ["usage: wolf remove <site> [--now]"])
                }
                if instant {
                    guard state.config.passphrase != nil else {
                        return .init(ok: false, lines: ["no partner passphrase is set, so instant removal is disabled. Use `wolf remove \(site)` to queue it."])
                    }
                    if state.removeWithPassphrase(site, passphrase: req.passphrase ?? "") {
                        try store.save(state); try Enforcer.apply(state)
                        Audit.record("remove --now (passphrase): \(site)")
                        return .init(ok: true, lines: ["removed immediately: \(site)"])
                    }
                    return .init(ok: false, lines: ["passphrase incorrect — nothing changed."])
                }
                guard let r = state.requestRemoval(site, now: now) else {
                    return .init(ok: false, lines: ["\(site) is not currently blocked (or already queued)."])
                }
                try store.save(state); try Enforcer.apply(state)
                Audit.record("remove queued: \(r.domain) → \(fmt(r.unlockAt))")
                return .init(ok: true, lines: [
                    "removal queued. \(r.domain) stays blocked until \(fmt(r.unlockAt)).",
                    "changed your mind? re-committing keeps you safe: `wolf add \(r.domain)`"])

            case "cancel":
                guard let site = req.args.first, let d = Domain.canonical(site) else {
                    return .init(ok: false, lines: ["usage: wolf cancel <site>"])
                }
                let before = state.pendingRemovals.count
                state.pendingRemovals.removeAll { $0.domain == d }
                guard state.pendingRemovals.count < before else {
                    return .init(ok: false, lines: ["no pending removal for \(d)."])
                }
                try store.save(state); try Enforcer.apply(state)
                Audit.record("cancel removal: \(d)")
                return .init(ok: true, lines: ["cancelled pending removal — \(d) stays blocked."])

            case "enable":
                state.enable(); try store.save(state); try Enforcer.apply(state)
                Audit.record("enable")
                return .init(ok: true, lines: ["Wolf re-enabled — \(state.blocked.count) site(s) enforced."])

            default:
                return .init(ok: false, lines: ["unsupported command over daemon: \(req.cmd)"])
            }
        } catch {
            return .init(ok: false, lines: ["error: \(error)"])
        }
    }
}
