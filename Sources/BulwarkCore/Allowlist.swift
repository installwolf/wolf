import Foundation

/// Domains Bulwark refuses to block, ever. This is the anti-footgun rail: it
/// stops you from accidentally sinkholing Apple/OS services (or your own
/// bank/work) and locking yourself out of a working Mac.
///
/// Matching is suffix-aware: protecting `apple.com` also protects
/// `gsa.apple.com`, `swscan.apple.com`, etc.
public enum Allowlist {
    /// Built-in, non-removable protections for critical Apple / macOS endpoints.
    public static let critical: [String] = [
        "apple.com",           // swscan, gsa, gdmf, ocsp, push, mesu, gs-loc, …
        "icloud.com",
        "icloud-content.com",
        "cdn-apple.com",
        "mzstatic.com",
        "aaplimg.com",
        "me.com",
        "apple-cloudkit.com",
    ]

    /// True if `domain` is the apex of, or a subdomain of, any protected entry.
    public static func isProtected(_ domain: String, extra: Set<String> = []) -> Bool {
        let all = critical + extra
        return all.contains { p in domain == p || domain.hasSuffix("." + p) }
    }
}
