import Foundation

/// Applies `WolfState` to the live system and self-heals it. This is the
/// layer that has real side effects; it must run as root.
///
/// Layers (see DESIGN.md): /etc/hosts sinkhole + pf anchor blocking DoH/DoT +
/// the schg immutable flag on every managed file. The daemon calls `apply`
/// on a loop so any tampering is reverted within seconds.
public enum Enforcer {

    /// Render state onto every enforcement layer and re-harden. When the state
    /// is disabled (kill switch), clear every layer instead.
    public static func apply(_ state: WolfState) throws {
        guard state.enabled else { try clearAll(); return }
        let domains = state.blocked.sorted()
        try writeHosts(domains)
        try writePfAnchor()
        reloadPf()
        hardenAll()
    }

    /// Remove all enforcement: empty the hosts block, flush the pf anchor, and
    /// drop immutable flags. Used by `disable` and `panic`.
    public static func clearAll() throws {
        unhardenAll()
        try writeHosts([])
        Shell.run("/sbin/pfctl", ["-a", "wolf", "-F", "all"])
        setImmutable(false, path: Paths.pfAnchor)
        try? "# managed by wolf (disabled)\n".write(toFile: Paths.pfAnchor, atomically: true, encoding: .utf8)
        flushDNSCache()
    }

    // MARK: /etc/hosts

    static func writeHosts(_ domains: [String]) throws {
        let path = Paths.hosts
        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let updated = HostsRenderer.splice(into: existing, domains: domains)
        guard updated != existing else { return }
        setImmutable(false, path: path)
        do {
            try updated.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw WolfError.io("cannot write \(path) (need root?): \(error.localizedDescription)")
        }
        setImmutable(true, path: path)
        flushDNSCache()
    }

    // MARK: pf

    static func writePfAnchor() throws {
        let path = Paths.pfAnchor
        let rules = PfRenderer.anchorRules()
        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard rules != existing else { return }
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        setImmutable(false, path: path)
        do {
            try rules.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw WolfError.io("cannot write \(path): \(error.localizedDescription)")
        }
        setImmutable(true, path: path)
    }

    /// (Re)load the Wolf pf anchor. Assumes pf.conf references it (installer adds that).
    static func reloadPf() {
        Shell.run("/sbin/pfctl", ["-E"])                       // enable pf (ref-counted)
        Shell.run("/sbin/pfctl", ["-a", "wolf", "-f", Paths.pfAnchor])
    }

    static func flushDNSCache() {
        Shell.run("/usr/bin/dscacheutil", ["-flushcache"])
        Shell.run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }

    // MARK: immutability

    /// Set/clear the system immutable flag. Root-only; a no-op speed bump for a
    /// determined root user, but it defeats casual edits and scripted tampering.
    public static func setImmutable(_ on: Bool, path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        Shell.run("/usr/bin/chflags", [on ? "schg" : "noschg", path])
    }

    public static func hardenAll() {
        for path in Paths.immutableTargets { setImmutable(true, path: path) }
    }

    public static func unhardenAll() {
        for path in Paths.immutableTargets { setImmutable(false, path: path) }
    }
}
