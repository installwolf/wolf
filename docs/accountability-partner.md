# RFC: Remote, informed accountability partner

Status: **proposed** · Supersedes DESIGN.md roadmap item #2 ("Accountability
reporting") with a concrete design.

## Problem

Today the accountability partner is a **passive keyholder who must be physically
present**. `wolf set-passphrase` reads the passphrase over `getpass` on the
*user's own keyboard* (`Sources/wolf/main.swift:207`), and the partner never
hears from Wolf again. Two consequences:

1. **Presence requirement.** Real partners are remote (a friend, a sponsor, a
   spouse at work). "Have them type it while you look away" doesn't scale and
   isn't what anyone actually does.
2. **No signal.** The partner holds a key but sees nothing. The literature and
   the recovery communities agree the decisive factor for durable change is a
   partner who *sees activity* — Wolf currently delivers none.

The enforcement half of Wolf (watchdog, pf, immutability) is strong. The
human-in-the-loop half is a stub. This RFC makes the partner **remote** and
**informed**, and does it **end-to-end encrypted** so Wolf never becomes a
company holding radioactive activity data — which is also the product's
differentiator against Covenant Eyes / Ever Accountable (both upload your data).

## Design principles (non-negotiable)

1. **Never weaken the gate.** The partner→Mac channel may carry *only* a
   passphrase hash at enrollment. Nothing in this feature can remove a block,
   shorten a cooldown, or disable Wolf. Notifications are strictly one-way
   (Mac → partner). (See the standing rule: a soft gatekeeper must never hold the
   removal key.)
2. **Suppression must be visible, not possible-and-silent.** An informed-partner
   feature is theater if the user can quietly turn it off. The user may be able to
   *stop* messages (pull the network cable) but must not be able to stop their
   *absence* from being noticed. → dead-man's-switch heartbeat.
3. **Un-enrolling a partner is gated like everything else.** Removing/replacing
   the partner requires the passphrase or the cooldown, exactly like removing a
   block, and it notifies the partner first.
4. **The relay is dumb.** It forwards ciphertext keyed by an opaque channel id
   and reports liveness. It never holds plaintext, browsing data, or the
   passphrase. E2E is the privacy wedge; keep it real.
5. **v1 reports gate events, not browsing.** What ships first is config/gate
   events ("removal requested for X", "panic", "cooldown lowered") — benign,
   low-sensitivity. *Which blocked sites the user tried to reach* is far more
   sensitive, needs the Network Extension layer, and is a later, explicitly
   opt-in phase.

## Data model changes

`WolfConfig` (`Sources/WolfCore/State.swift`) gains an optional partner channel,
decoded tolerantly like `protectedDomains`/`enabled` already are:

```swift
public struct PartnerChannel: Codable, Equatable {
    public var publicKeyB64: String   // partner's X25519 public key (we seal to this)
    public var channelId: String      // opaque relay routing id (no PII)
    public var relayURL: String       // where the daemon POSTs sealed blobs + heartbeat
    public var enrolledAt: Date
}
// in WolfConfig:
public var partner: PartnerChannel?   // decodeIfPresent → nil for old state files
```

Note the passphrase model is unchanged: `config.passphrase: PassphraseHash?`
already stores only a salted PBKDF2 hash (`Sources/WolfCore/Passphrase.swift`).
Remote enrollment makes this *stronger* — the plaintext passphrase never touches
the user's machine at all; only the hash arrives.

## Pairing / remote enrollment

Goal: partner sets the passphrase and hands Wolf their public key, without being
present and without the user ever seeing the plaintext.

```
wolf pair start
  └─ daemon generates ephemeral X25519 keypair + a 6-word pairing code (SAS)
     and displays it (+ QR).                                         [Mac]

partner app  (iOS/PWA — separate, minimal; not in this repo)
  └─ enters code / scans QR
  └─ ECDH with the Mac's ephemeral key over the relay; both sides show the
     same SAS words → user + partner confirm verbally → MITM-proof
  └─ partner picks the passphrase locally, computes PassphraseHash
     (same PBKDF2 params), and sends { hash, partnerPublicKey } sealed to
     the Mac's ephemeral key.                                        [partner]

Mac
  └─ stores config.passphrase = hash;  config.partner = { publicKey, channelId, relayURL }
  └─ Audit.record("partner enrolled"); Notifier.enqueue(.partnerEnrolled)
```

Re-enrollment / rotation goes through the same gate as `set-passphrase` today
(changing an existing passphrase requires the current one). The user can never
enroll *themselves* as the partner in a way that reveals the passphrase, because
they only ever receive the hash.

Phase-1 fallback with **zero server**: run the pairing exchange over the LAN
(Bonjour) or a copy/paste of two QR blobs. This alone delivers "partner sets the
passphrase without being present," the single biggest UX unlock, before any relay
exists.

## Notification path

### Choke point
Every gate event already funnels through **one** call: `Audit.record(...)` in
`CommandProcessor.handle` (`Sources/WolfCore/CommandProcessor.swift`) and the
setup/`panic` commands in the CLI. Wrap it:

```swift
// Audit.record additionally enqueues a sealed copy when a partner is enrolled.
Audit.record(event)        // append-only local log (unchanged)
  → if let p = config.partner { Notifier.enqueue(event, sealedTo: p) }
```

So the notification set == the audit set, for free. No event can be reported
without also being in the tamper-evident local log, and vice-versa.

### Outbox (new: `Sources/WolfCore/Notify.swift`)
`Notifier.enqueue` seals the event and appends it to a **root-owned, append-only
outbox** (mirrors `Audit`'s `sappnd` design). Sealing uses CryptoKit — no
external dependency:

```
Curve25519.KeyAgreement (ephemeral) → shared secret with partner.publicKey
  → HKDF-SHA256 → ChaChaPoly.seal(eventJSON)
outbox line = { ts, ephemeralPub, nonce, ciphertext, tag }   // all base64
```

Event JSON is a benign gate event, e.g. `{"t":"remove_queued","domain":"…",
"unlockAt":"…"}`. The relay and anyone on the wire see only ciphertext.

### Delivery worker (in `wolfd`)
A second responsibility in the daemon (`Sources/wolfd/main.swift`), on its own
cadence beside the 15s enforcement `cycle()`:

```
every ~60s:  drain outbox → POST sealed blobs to relayURL/channelId
             on 2xx: mark delivered (advance an outbox cursor)
every ~5m:   POST a signed heartbeat to relayURL/channelId/heartbeat
```

Because `wolfd` runs as root under `KeepAlive`, the user can't kill the worker
without the same effort as defeating enforcement, and the outbox/partner config
are immutable + gated.

### Dead-man's switch (closes the "just block the relay" hole)
The partner app treats **silence as signal**. If heartbeats stop for > T
(say 30 min), the partner is alerted: *"Wolf went quiet on <name>'s Mac —
network blocked, killed, or uninstalled."* You can stop the messages; you cannot
stop the absence from being noticed. `panic` and `disable` also fire an immediate
best-effort notification *before* teardown (panic already records to the audit
log before wiping — same ordering), with the heartbeat as backstop.

## Events in v1

Emitted (all already exist as audit events except heartbeat):

- `partner_enrolled` / `partner_changed`
- `passphrase_set`
- `add` (new site blocked — a *positive* signal worth sending)
- `remove_queued` (+ unlockAt), `remove_now_passphrase`, `cancel`
- `cooldown_raised` / `cooldown_lowered`
- `disable`, `enable`
- `panic` (with "everything wiped")
- `heartbeat` (liveness only)

Explicitly **not** in v1: which blocked domains the user *attempted* to visit.
That needs the flow-inspection / Network Extension layer, is much more sensitive,
and is a later opt-in phase.

## Threat model additions

| Attack | Mitigation |
|---|---|
| User firewalls / blackholes the relay | Heartbeat stops → partner alerted to the silence |
| User kills `wolfd` or uninstalls | `KeepAlive` relaunches; if truly gone, heartbeat stops → alert |
| User un-enrolls the partner | Gated by passphrase/cooldown like a block removal; notifies partner first |
| Relay is compromised / subpoenaed | Only ciphertext + opaque channel ids + timing; no plaintext, no passphrase |
| MITM during pairing | Short-authentication-string (6 words) confirmed out-of-band |
| Notifications used as a bypass | Channel is one-way Mac→partner; partner→Mac carries only the hash at enroll |
| Replay of old sealed events | Per-event nonce + monotonic ts; relay dedups by (channelId, ts) |

Unchanged residual holes (documented in DESIGN.md): a determined admin booting to
Recovery, a different device, etc. This RFC does not claim to close those — it
makes *going dark* observable to a human, which is the point.

## Privacy posture (the differentiator, stated plainly)

The relay is a store-and-forward pipe for ciphertext. It has no user accounts
tied to browsing, no screenshots, no plaintext events, and never the passphrase
(only the hash ever existed, and it lives on the Mac and the partner's device —
never the relay). This is deliberately the opposite of the incumbents and is the
reason a privacy-conscious person would choose Wolf.

## Phasing

- **Phase 1 (biggest win / least infra):** `PartnerChannel` in state; `wolf pair`
  over LAN/QR; remote **hash-only** passphrase enrollment; `Notifier` + sealed
  outbox written locally. Ships the "partner without presence" unlock and the
  crypto core with no server.
- **Phase 2:** the dumb relay + delivery worker + heartbeat → real remote
  notifications and the dead-man's switch. This is the part that needs a tiny
  stateless service.
- **Phase 3 (later, sensitive, opt-in):** attempt reporting (which blocked
  domains were hit), riding on the Network Extension flow-inspection layer.

## Testing (TDD, per the WolfCore style)

`WolfCore` is pure and injectable (`TimeSource`), so:

- `PartnerChannel` Codable tolerance: old state files with no `partner` decode to
  `nil` (mirror the existing `protectedDomains`/`enabled` tests).
- `Notifier.enqueue` fires for exactly the gate events, and never when
  `config.partner == nil`.
- Seal → open round-trip with a known keypair; wrong key fails; nonce is unique.
- Pairing SAS derivation is deterministic for a given ECDH transcript.
- Outbox is append-only and the delivery cursor only advances on ack (simulated).

Relay and the partner app are separate deliverables (out of this repo) and get
their own tests; keep all crypto that matters on the *client* side so it stays in
the audited open-source core.
