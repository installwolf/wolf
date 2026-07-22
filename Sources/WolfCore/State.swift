import Foundation

public enum WolfError: Error, Equatable {
    case crypto(String)
    case invalidDomain(String)
    case io(String)
}

/// Abstracts "now" so cooldown logic is testable and so we can later harden
/// against clock-rollback attacks (the daemon persists a monotonic marker).
public protocol TimeSource { var now: Date { get } }
public struct SystemTime: TimeSource {
    public init() {}
    public var now: Date { Date() }
}

/// Outcome of an `add`, so callers can explain refusals (invalid / protected).
public enum AddResult: Equatable {
    case added(String)
    case alreadyBlocked(String)
    case invalid(String)
    case protectedDomain(String)
}

/// A queued request to unblock a domain. It stays blocked until `unlockAt`.
public struct RemovalRequest: Codable, Equatable {
    public var domain: String
    public var requestedAt: Date
    public var unlockAt: Date
}

/// A remote accountability partner. Wolf seals event notifications to
/// `publicKeyB64` (X25519) and routes them via `relayURL`/`channelId`. Enrolled
/// remotely (see docs/accountability-partner.md) so the plaintext passphrase
/// never touches the user's machine — only the resulting `PassphraseHash` does.
/// The relay only ever sees ciphertext keyed by the opaque `channelId`.
public struct PartnerChannel: Codable, Equatable {
    public var publicKeyB64: String
    public var channelId: String
    public var relayURL: String
    public var enrolledAt: Date

    public init(publicKeyB64: String, channelId: String,
                relayURL: String, enrolledAt: Date) {
        self.publicKeyB64 = publicKeyB64
        self.channelId = channelId
        self.relayURL = relayURL
        self.enrolledAt = enrolledAt
    }
}

public struct WolfConfig: Codable, Equatable {
    /// Default cooldown before a queued removal takes effect. 48h.
    public var cooldownSeconds: TimeInterval
    /// Optional accountability-partner passphrase for instant override.
    public var passphrase: PassphraseHash?
    /// User-added domains that may never be blocked (bank, work, …).
    public var protectedDomains: Set<String>
    /// Optional remote accountability partner to notify of gate events.
    public var partner: PartnerChannel?

    public init(cooldownSeconds: TimeInterval = 48 * 3600,
                passphrase: PassphraseHash? = nil,
                protectedDomains: Set<String> = [],
                partner: PartnerChannel? = nil) {
        self.cooldownSeconds = cooldownSeconds
        self.passphrase = passphrase
        self.protectedDomains = protectedDomains
        self.partner = partner
    }

    // Tolerate older state files that predate `protectedDomains` / `partner`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cooldownSeconds = try c.decode(TimeInterval.self, forKey: .cooldownSeconds)
        passphrase = try c.decodeIfPresent(PassphraseHash.self, forKey: .passphrase)
        protectedDomains = try c.decodeIfPresent(Set<String>.self, forKey: .protectedDomains) ?? []
        partner = try c.decodeIfPresent(PartnerChannel.self, forKey: .partner)
    }
}

/// The single source of truth. Persisted as JSON, owned by root, made
/// immutable on disk. All mutation policy (add=instant, remove=gated) lives here.
public struct WolfState: Codable, Equatable {
    public var blocked: Set<String>
    public var pendingRemovals: [RemovalRequest]
    public var config: WolfConfig
    /// When false, the daemon clears all enforcement. Flipped by disable/enable.
    public var enabled: Bool

    public init(blocked: Set<String> = [],
                pendingRemovals: [RemovalRequest] = [],
                config: WolfConfig = WolfConfig(),
                enabled: Bool = true) {
        self.blocked = blocked
        self.pendingRemovals = pendingRemovals
        self.config = config
        self.enabled = enabled
    }

    // Tolerate older state files that predate `enabled`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocked = try c.decode(Set<String>.self, forKey: .blocked)
        pendingRemovals = try c.decode([RemovalRequest].self, forKey: .pendingRemovals)
        config = try c.decode(WolfConfig.self, forKey: .config)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    /// Add is always instant and cancels any pending removal (a change of heart
    /// while committing should re-commit, never accidentally unblock). Refuses
    /// protected domains so you can't lock yourself out of a working Mac.
    @discardableResult
    public mutating func add(_ raw: String) -> AddResult {
        guard let d = Domain.canonical(raw) else { return .invalid(raw) }
        if Allowlist.isProtected(d, extra: config.protectedDomains) { return .protectedDomain(d) }
        let isNew = blocked.insert(d).inserted
        pendingRemovals.removeAll { $0.domain == d }
        return isNew ? .added(d) : .alreadyBlocked(d)
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

    // MARK: kill switch

    /// Clean, gated shutdown: requires the partner passphrase. Keeps config so
    /// the user can `enable` again later.
    @discardableResult
    public mutating func disable(passphrase: String) -> Bool {
        guard let stored = config.passphrase,
              Passphrase.verify(passphrase, against: stored) else { return false }
        enabled = false
        return true
    }

    public mutating func enable() { enabled = true }
}
