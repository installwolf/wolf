# Wolf — build tracker

Durable, cross-session checklist. Priorities come from
[COMPETITIVE.md](COMPETITIVE.md); the accountability design is
[docs/accountability-partner.md](docs/accountability-partner.md).

The guiding priority: Wolf's enforcement half is strong; the **human-in-the-loop
half** is the gap. Make the partner *remote* and *informed* before hardening the
lock further.

## Now — Accountability partner, Phase 1 (partner without presence, zero server)

- [x] **1. `PartnerChannel` data model** — added optional `partner` to
      `WolfConfig` with tolerant decoding (old `state.json` → `nil`).
- [ ] **2. `Notifier` + sealed outbox** (`Sources/WolfCore/Notify.swift`) —
      CryptoKit X25519 seal/open round-trip; root-owned append-only outbox. TDD.
- [ ] **3. Wire the choke point** — `Audit.record` also enqueues to `Notifier`
      when a partner is enrolled; fires for exactly the gate events. TDD.
- [ ] **4. `wolf pair` (LAN/QR)** — remote, hash-only passphrase enrollment; the
      plaintext passphrase never touches the user's Mac.

## Next — Accountability Phase 2 (real remote delivery)

- [ ] Dumb store-and-forward relay (ciphertext only; separate deliverable).
- [ ] Delivery worker in `wolfd` — drain outbox → POST; advance cursor on ack.
- [ ] Dead-man's-switch heartbeat + partner-side "went quiet" alert.

## Later

- [ ] **Mobile coverage** — an unblocked phone defeats a locked Mac (COMPETITIVE
      gap #2). iOS DNS-profile / content-filter companion, partner-controlled.
- [ ] **Onboarding for non-sysadmins** — guided setup beyond `brew` +
      `sudo wolf bootstrap`; dead-simple partner invite.
- [ ] **Network Extension content filter** — DoH/DoT-immune enforcement
      (DESIGN.md roadmap #1). Deepens the lock; not the current priority.
- [ ] **Accountability Phase 3** — attempt reporting (which blocked domains were
      hit), riding the NE flow-inspection layer. Sensitive; explicitly opt-in.

## Done

- [x] Competitive positioning doc ([COMPETITIVE.md](COMPETITIVE.md)).
- [x] Accountability partner RFC ([docs/accountability-partner.md](docs/accountability-partner.md)).
