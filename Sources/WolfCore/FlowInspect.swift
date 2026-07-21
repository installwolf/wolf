import Foundation

/// Extracts the destination hostname from a flow's first outbound bytes.
///
/// This is what makes the Network Extension immune to DoH/VPN: instead of
/// trusting DNS, we read the host directly out of the connection itself — the
/// TLS ClientHello's SNI field (for HTTPS) or the HTTP Host header (plaintext).
/// Both are parsed defensively; partial/malformed input returns nil (→ allow),
/// never a crash.
public enum TLSInspect {
    /// The SNI host_name from a TLS ClientHello record, lowercased, or nil.
    public static func sniHostName(_ data: Data) -> String? {
        let b = [UInt8](data)
        let n = b.count
        func u16(_ i: Int) -> Int? { i + 1 < n ? Int(b[i]) << 8 | Int(b[i + 1]) : nil }

        guard n >= 5, b[0] == 0x16 else { return nil }   // TLS handshake record
        var p = 5
        guard p < n, b[p] == 0x01 else { return nil }    // ClientHello
        p += 4                                            // handshake type(1) + length(3)
        p += 2 + 32                                       // client_version(2) + random(32)
        guard p < n else { return nil }
        p += 1 + Int(b[p])                                // session_id
        guard let cipherLen = u16(p) else { return nil }
        p += 2 + cipherLen                                // cipher_suites
        guard p < n else { return nil }
        p += 1 + Int(b[p])                                // compression_methods
        guard let extsLen = u16(p) else { return nil }
        p += 2
        let extsEnd = min(p + extsLen, n)

        while p + 4 <= extsEnd {
            guard let extType = u16(p), let extLen = u16(p + 2) else { return nil }
            p += 4
            if extType == 0x0000 {                        // server_name
                guard let listLen = u16(p) else { return nil }
                var q = p + 2
                let listEnd = min(p + 2 + listLen, n)
                while q + 3 <= listEnd {
                    let nameType = b[q]
                    guard let nameLen = u16(q + 1) else { return nil }
                    q += 3
                    guard q + nameLen <= n else { return nil }
                    if nameType == 0x00 {                 // host_name
                        return String(decoding: b[q..<q + nameLen], as: UTF8.self)
                            .lowercased()
                    }
                    q += nameLen
                }
            }
            p += extLen
        }
        return nil
    }
}

public enum HTTPInspect {
    /// The Host header value from a plaintext HTTP/1.x request, lowercased,
    /// port stripped, or nil.
    public static func hostHeader(_ data: Data) -> String? {
        // Only inspect the request head; ignore bodies.
        let head = data.prefix(4096)
        guard let text = String(data: head, encoding: .ascii) ?? String(data: head, encoding: .utf8)
        else { return nil }
        // Must look like an HTTP request line to avoid false positives.
        guard let firstLine = text.split(separator: "\r\n", maxSplits: 1).first,
              firstLine.contains(" HTTP/") else { return nil }
        for line in text.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "host" {
                var host = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
                if let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }
                return host.isEmpty ? nil : host
            }
        }
        return nil
    }
}

/// Blocklist matching for a live hostname: true if the host is, or is a
/// subdomain of, any blocked domain. Shared by the CLI and the extension.
public enum Rules {
    public static func isBlocked(_ host: String, in blocked: Set<String>) -> Bool {
        var h = host.lowercased()
        if h.hasSuffix(".") { h.removeLast() }
        if let colon = h.firstIndex(of: ":") { h = String(h[..<colon]) }
        guard !h.isEmpty else { return false }
        return blocked.contains { d in h == d || h.hasSuffix("." + d) }
    }
}
