import NetworkExtension
import OSLog
import WolfCore

/// The content-filter system extension. macOS routes every socket flow through
/// this, so it filters by the *actual destination hostname* read from the
/// connection (TLS SNI / HTTP Host) rather than DNS — which is why it holds even
/// with DoH, iCloud Private Relay, or a full-tunnel VPN active.
final class FilterDataProvider: NEFilterDataProvider {
    private let log = Logger(subsystem: "com.installwolf.filter", category: "filter")
    private var blocked: Set<String> = []
    private var blockedMTime: Date = .distantPast

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        reloadBlocklistIfNeeded()
        log.info("filter started, \(self.blocked.count) domains")
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socket = flow as? NEFilterSocketFlow,
              socket.socketProtocol == IPPROTO_TCP else { return .allow() }

        reloadBlocklistIfNeeded()
        guard !blocked.isEmpty else { return .allow() }

        // Peek the first outbound bytes so we can read the TLS ClientHello SNI
        // (HTTPS) or the HTTP Host header (plaintext) and decide from the real
        // destination, not from DNS.
        return .filterDataVerdict(withFilterInbound: false, peekInboundBytes: 0,
                                  filterOutbound: true, peekOutboundBytes: 4096)
    }

    override func handleOutboundData(from flow: NEFilterFlow,
                                     readBytesStartOffset offset: Int,
                                     readBytes: Data) -> NEFilterDataVerdict {
        let host = TLSInspect.sniHostName(readBytes) ?? HTTPInspect.hostHeader(readBytes)
        if let host, Rules.isBlocked(host, in: blocked) {
            log.info("blocked \(host, privacy: .public)")
            return .drop()
        }
        return .allow()  // allow and stop filtering this flow
    }

    /// Refresh from the shared container only when the file has changed.
    private func reloadBlocklistIfNeeded() {
        guard let url = SharedStore.blocklistURL,
              let mtime = try? FileManager.default
                .attributesOfItem(atPath: url.path)[.modificationDate] as? Date,
              mtime > blockedMTime else { return }
        blocked = SharedStore.readBlocklist()
        blockedMTime = mtime
    }
}
