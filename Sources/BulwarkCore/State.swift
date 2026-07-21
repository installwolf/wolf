import Foundation

public enum BulwarkError: Error, Equatable {
    case crypto(String)
    case invalidDomain(String)
    case io(String)
}

/// Abstracts "now" so cooldown logic is testable and so we can later harden
/// against clock-rollback attacks (the daemon can persist a monotonic marker).
public protocol TimeSource { var now: Date { get } }
public struct SystemTime: TimeSource {
    public init() {}
    public var now: Date { Date() }
}

/// A queued request to unblock a domain. It stays blocked until `unlockAt`.
public struct RemovalRequest: Codable, Equatable {
    public var domain: String
    public var requestedAt: Date
    public var unlockAt: Date
}

public struct BulwarkConfig: Codable, Equatable {
    /// Default cooldown before a queued removal takes effect. 48h.
    public var cooldownSeconds: TimeInterval
    /// Optional accountability-partner passphrase for instant override.
    public var passphrase: PassphraseHash?

    public init(cooldownSeconds: TimeInterval = 48 * 3600, passphrase: PassphraseHash? = nil) {
        self.cooldownSeconds = cooldownSeconds
        self.passphrase = passphrase
    }
}

/// The single source of truth. Persisted as JSON, owned by root, made
/// immutable on disk. All mutation policy (add=instant, remove=gated) lives here.
public struct BulwarkState: Codable, Equatable {
    public var blocked: Set<String>
    public var pendingRemovals: [RemovalRequest]
    public var config: BulwarkConfig

    public init(blocked: Set<String> = [],
                pendingRemovals: [RemovalRequest] = [],
                config: BulwarkConfig = BulwarkConfig()) {
        self.blocked = blocked
        self.pendingRemovals = pendingRemovals
        self.config = config
    }

    /// Add is always instant and cancels any pending removal (a change of heart
    /// while committing should re-commit, never accidentally unblock).
    @discardableResult
    public mutating func add(_ raw: String) -> String? {
        guard let d = Domain.canonical(raw) else { return nil }
        blocked.insert(d)
        pendingRemovals.removeAll { $0.domain == d }
        return d
    }

    /// Queue a removal. It stays blocked until the cooldown elapses. Idempotent:
    /// a second request does not reset or shorten the existing timer.
    @discardableResult
    public mutating func requestRemoval(_ raw: String, now: Date) -> RemovalRequest? {
        guard let d = Domain.canonical(raw), blocked.contains(d) else { return nil }
        if let existing = pendingRemovals.first(where: { $0.domain == d }) { return existing }
        let req = RemovalRequest(domain: d, requestedAt: now,
                                 unlockAt: now.addingTimeInterval(config.cooldownSeconds))
        pendingRemovals.append(req)
        return req
    }

    /// Instant removal via the partner passphrase.
    @discardableResult
    public mutating func removeWithPassphrase(_ raw: String, passphrase: String) -> Bool {
        guard let d = Domain.canonical(raw),
              let stored = config.passphrase,
              Passphrase.verify(passphrase, against: stored) else { return false }
        blocked.remove(d)
        pendingRemovals.removeAll { $0.domain == d }
        return true
    }

    /// Called by the daemon: remove domains whose cooldown has elapsed.
    /// Returns the domains that were unblocked.
    @discardableResult
    public mutating func drainDue(now: Date) -> [String] {
        let due = pendingRemovals.filter { $0.unlockAt <= now }.map(\.domain)
        for d in due { blocked.remove(d) }
        pendingRemovals.removeAll { $0.unlockAt <= now }
        return due.sorted()
    }
}
