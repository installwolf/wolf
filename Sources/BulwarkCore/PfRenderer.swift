import Foundation

/// Renders the pf anchor ruleset. Its job is to close the DNS-over-HTTPS /
/// DNS-over-TLS holes that would otherwise let a browser resolve a blocked
/// domain out from under `/etc/hosts`.
public enum PfRenderer {
    /// Well-known public DoH resolver IPs. Blocking :443 to these forces DNS
    /// back onto the system resolver, which honors `/etc/hosts`.
    static let dohResolvers: [String] = [
        "1.1.1.1", "1.0.0.1",           // Cloudflare
        "8.8.8.8", "8.8.4.4",           // Google
        "9.9.9.9", "149.112.112.112",   // Quad9
        "94.140.14.14", "94.140.15.15", // AdGuard
        "208.67.222.222", "208.67.220.220", // OpenDNS
    ]

    public static func anchorRules() -> String {
        var lines = [
            "# Bulwark pf anchor — blocks DNS-over-HTTPS/TLS bypass. Managed; do not edit.",
            "block drop out proto tcp to { \(dohResolvers.joined(separator: ", ")) } port 443",
            "block drop out proto { tcp udp } to any port 853", // DoT
        ]
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
