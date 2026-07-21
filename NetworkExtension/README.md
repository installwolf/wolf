# Wolf Content Filter (Network Extension)

The on-device content filter — the layer that holds even with **DoH, iCloud
Private Relay, or a full-tunnel VPN** active. It inspects each connection's real
destination (TLS SNI / HTTP Host) at the socket layer, so it doesn't depend on
DNS at all.

## Architecture

- **`WolfFilter`** — the system extension (`NEFilterDataProvider`). Peeks the
  first outbound bytes of each TCP flow, extracts the hostname, and drops it if
  it's on the blocklist. All parsing/matching lives in the unit-tested
  `WolfCore` (`TLSInspect`, `HTTPInspect`, `Rules`).
- **`WolfFilterHost`** ("Wolf Filter.app") — activates the system extension,
  enables the content filter via `NEFilterManager`, and mirrors Wolf's
  blocklist (`state.json`) into the shared App Group container.
- **`Shared/SharedStore`** — the App Group (`group.com.installwolf`) bridge.

The `wolf` CLI + `wolfd` daemon remain the source of truth for the blocklist and
the removal gate. This extension is an additional enforcement layer, not a
replacement for hosts+pf.

## Building it (needs your Apple Developer account)

Everything is wired **except** signing — there were no signing identities on the
build machine. To finish:

1. **Generate the Xcode project:**
   ```bash
   cd NetworkExtension && xcodegen generate && open WolfFilter.xcodeproj
   ```
2. **Set your Team ID:** in `project.yml` set `DEVELOPMENT_TEAM: "<YOUR_TEAM_ID>"`
   (or pick your team per-target in Xcode ▸ Signing & Capabilities), then
   re-run `xcodegen generate`.
3. **Register the App Group + NetworkExtension capability** for both bundle IDs
   in your developer account (Xcode's automatic signing will offer to do this):
   - `com.installwolf` (host) · `com.installwolf.filter` (extension)
   - App Group: `group.com.installwolf`
   - Capability: Network Extensions → Content Filtering
4. **Build & run** `WolfFilterHost`, click **Set Up Filter**, and approve the two
   macOS prompts (system extension, then content filter).

## Verifying it works

With the filter enabled, turn **on** Firefox DoH / iCloud Private Relay / your
VPN and confirm a blocked site still fails — that's the whole point of this layer
versus hosts+pf.

## Status

- ✅ Hostname extraction + matching: written and unit-tested in `WolfCore`.
- ✅ Extension + host sources: type-check against the SDK.
- ⏳ Build/sign/run: needs your Team ID and on-device approval (above).
