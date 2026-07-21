import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Verdict on whether a domain actually exists, used to keep typos out of the
/// blocklist. `unknown` is deliberately distinct from `notFound` so callers can
/// fail *open* when the machine is offline (never trap the user), and refuse
/// only when a domain is provably nonexistent.
public enum DomainReachability: Sendable, Equatable {
    case reachable   // resolves in DNS
    case notFound    // provably does not exist
    case unknown     // couldn't tell (offline / resolver error) — treat as reachable
}

/// Checks whether a domain resolves. Injected into the command processor so the
/// existence check can be stubbed in tests without touching the network.
public protocol DomainResolver: Sendable {
    func check(_ domain: String) -> DomainReachability
}

/// Real resolver backed by `getaddrinfo`. To distinguish a genuinely
/// nonexistent domain from a machine that simply has no DNS, it falls back to
/// resolving a highly-available anchor: if the target fails but the anchor
/// succeeds, the target is nonexistent; if both fail, we're offline (`unknown`).
public struct SystemDomainResolver: DomainResolver {
    private let anchor: String

    /// `apple.com` is a built-in, never-blockable protection (see `Allowlist`),
    /// so it always reflects real connectivity rather than a self-inflicted sinkhole.
    public init(anchor: String = "apple.com") { self.anchor = anchor }

    public func check(_ domain: String) -> DomainReachability {
        if resolves(domain) { return .reachable }
        return resolves(anchor) ? .notFound : .unknown
    }

    private func resolves(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, nil, &hints, &res)
        if res != nil { freeaddrinfo(res) }
        return rc == 0
    }
}
