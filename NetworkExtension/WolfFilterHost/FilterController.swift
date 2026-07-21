import Foundation
import SystemExtensions
@preconcurrency import NetworkExtension
import WolfCore

/// Drives the two macOS approval steps and keeps the shared blocklist current.
///   1. Activate the system extension (OSSystemExtensionRequest → user approves
///      in System Settings ▸ Login Items & Extensions).
///   2. Enable the content filter (NEFilterManager → "Wolf would like to filter
///      network content" prompt).
/// Then it mirrors Wolf's authoritative blocklist (state.json) into the App
/// Group container the extension reads.
@MainActor
final class FilterController: NSObject, ObservableObject {
    @Published var status = "Not set up"
    @Published var filterEnabled = false

    private let extensionIdentifier = "com.installwolf.filter"
    private let store = Store()

    // MARK: step 1 — system extension
    func activate() {
        status = "Requesting extension activation…"
        let req = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    // MARK: step 2 — content filter configuration
    func enableFilter() {
        let mgr = NEFilterManager.shared()
        mgr.loadFromPreferences { [weak self] error in
            guard let self else { return }
            if let error { self.status = "load error: \(error.localizedDescription)"; return }
            if mgr.providerConfiguration == nil {
                let cfg = NEFilterProviderConfiguration()
                cfg.filterSockets = true
                cfg.filterPackets = false
                mgr.providerConfiguration = cfg
                mgr.localizedDescription = "Wolf"
            }
            mgr.isEnabled = true
            mgr.saveToPreferences { err in
                if let err { self.status = "save error: \(err.localizedDescription)" }
                else { self.filterEnabled = true; self.status = "Filter enabled"; self.syncBlocklist() }
            }
        }
    }

    // MARK: blocklist bridge
    /// Read Wolf's authoritative state and mirror the blocked domains into the
    /// App Group container. Safe to call on a timer.
    func syncBlocklist() {
        guard let state = try? store.load() else { return }
        try? SharedStore.writeBlocklist(state.enabled ? state.blocked : [])
    }
}

extension FilterController: OSSystemExtensionRequestDelegate {
    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in self.status = "Approve Wolf in System Settings ▸ Login Items & Extensions" }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            self.status = "Extension activated"
            self.enableFilter()
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in self.status = "Activation failed: \(error.localizedDescription)" }
    }
}
