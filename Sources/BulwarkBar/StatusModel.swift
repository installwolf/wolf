import Foundation
import SwiftUI
import BulwarkCore

/// Observable bridge between the menu-bar UI and Bulwark. Reads state directly
/// (world-readable) and routes changes through the privileged CLI.
@MainActor
final class StatusModel: ObservableObject {
    @Published var state = BulwarkState()
    @Published var busy = false
    @Published var lastError: String?

    private let store = Store()

    func refresh() {
        state = (try? store.load()) ?? BulwarkState()
    }

    var blockedSorted: [String] { state.blocked.sorted() }

    func pending(for domain: String) -> RemovalRequest? {
        state.pendingRemovals.first { $0.domain == domain }
    }

    func add(_ raw: String) {
        guard let d = Domain.canonical(raw) else { lastError = "not a valid domain: \(raw)"; return }
        run(["add", d])
    }

    func queueRemoval(_ domain: String) { run(["remove", domain]) }
    func enable() { run(["enable"]) }
    func panic() { run(["panic", "--confirm"]) }

    private func run(_ args: [String]) {
        busy = true
        lastError = nil
        Task.detached {
            var err: String?
            do { _ = try PrivilegedRunner.runAdmin(args) }
            catch { err = error.localizedDescription }
            await MainActor.run {
                self.lastError = err
                self.busy = false
                self.refresh()
            }
        }
    }
}
