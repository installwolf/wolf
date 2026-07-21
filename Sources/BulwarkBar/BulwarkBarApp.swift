import SwiftUI
import AppKit
import BulwarkCore

@main
struct BulwarkBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = StatusModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.state.enabled ? "shield.fill" : "shield.slash")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Run as a menu-bar accessory (no Dock icon).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuView: View {
    @ObservedObject var model: StatusModel
    @State private var newSite = ""
    @State private var confirmingPanic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !model.state.enabled {
                Button { model.enable() } label: {
                    Label("Enforcement is OFF — click to re-enable", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            addRow
            Divider()
            blockedList
            Divider()
            footer

            if let err = model.lastError {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { model.refresh() }
        .task { while true { model.refresh(); try? await Task.sleep(for: .seconds(10)) } }
    }

    private var header: some View {
        HStack {
            Image(systemName: model.state.enabled ? "shield.fill" : "shield.slash")
                .foregroundStyle(model.state.enabled ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Bulwark").font(.headline)
                Text("\(model.state.blocked.count) blocked · cooldown \(hours(model.state.config.cooldownSeconds)) · passphrase \(model.state.config.passphrase == nil ? "not set" : "set")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
        }
    }

    private var addRow: some View {
        HStack {
            TextField("Block a site (e.g. pornhub.com)", text: $newSite)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitAdd)
            Button("Add", action: submitAdd)
                .buttonStyle(.borderedProminent)
                .disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
        }
    }

    private var blockedList: some View {
        Group {
            if model.blockedSorted.isEmpty {
                Text("Nothing blocked yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.blockedSorted, id: \.self) { d in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(d).font(.callout)
                                    if let p = model.pending(for: d) {
                                        Text("unblocks \(p.unlockAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption2).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                if model.pending(for: d) == nil {
                                    Button("Remove") { model.queueRemoval(d) }
                                        .buttonStyle(.borderless).font(.caption)
                                        .disabled(model.busy)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
            Spacer()
            Button("Panic", role: .destructive) { confirmingPanic = true }
                .buttonStyle(.borderless).foregroundStyle(.red)
                .confirmationDialog(
                    "Panic will disable Bulwark and WIPE your entire setup (blocklist, cooldown, passphrase). It's permanently logged. Use only for a real emergency.",
                    isPresented: $confirmingPanic, titleVisibility: .visible
                ) {
                    Button("Wipe everything", role: .destructive) { model.panic() }
                    Button("Cancel", role: .cancel) {}
                }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
        }
    }

    private func submitAdd() {
        let s = newSite.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        model.add(s)
        newSite = ""
    }

    private func hours(_ s: TimeInterval) -> String {
        let h = Int(s / 3600)
        return h >= 48 ? "\(h/24)d" : "\(h)h"
    }
}
