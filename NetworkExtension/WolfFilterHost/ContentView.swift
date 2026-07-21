import SwiftUI

struct ContentView: View {
    @ObservedObject var model: FilterController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: model.filterEnabled ? "shield.lefthalf.filled" : "shield.slash")
                    .font(.largeTitle)
                    .foregroundStyle(model.filterEnabled ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text("Wolf Content Filter").font(.title2).bold()
                    Text("On-device filtering — immune to DoH, Private Relay, and VPNs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            GroupBox {
                Text(model.status).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("""
            Setup is two macOS approvals:
            1. Approve the system extension (System Settings ▸ Login Items & Extensions).
            2. Allow the content filter when prompted.
            The filter reads Wolf's blocklist — manage sites with the `wolf` CLI.
            """)
            .font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("Set Up Filter") { model.activate() }
                    .buttonStyle(.borderedProminent)
                Button("Sync blocklist now") { model.syncBlocklist() }
                Spacer()
            }
        }
        .padding(20)
        .task {
            model.syncBlocklist()
            // keep the shared blocklist current with the daemon's state
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                model.syncBlocklist()
            }
        }
    }
}
