# Bulwark — Design & Threat Model

## Philosophy

Bulwark is a **commitment device**, not a fortress. The research consensus from
recovery communities and the vendors in this space (Cold Turkey, SelfControl,
Covenant Eyes, Tech Lockdown) is blunt: *pure local blocking on a self-owned
machine is necessary but never sufficient.* A sufficiently motivated admin will
eventually get around any single device's blocker.

So Bulwark optimizes for the thing that actually works: **making bypass slow,
effortful, and visible**, so the impulse passes before you can defeat it. Two
levers do the heavy lifting:

1. **Asymmetry** — adding a block is one command; removing one is a 48h wait or
   requires a passphrase you don't hold.
2. **A human in the loop** — the partner passphrase (and, on the roadmap,
   activity reporting) removes secrecy, which the literature says matters more
   for long-term change than access control.

## Architecture

```
 bulwark (CLI)  ──writes──▶  state.json  ◀──reads──  bulwarkd (root watchdog)
   add/remove/…             (root-owned,             every 15s:
   policy enforced          immutable)                 · drainDue(now)
   in BulwarkCore                                       · Enforcer.apply(state)
                                                        · advance clock floor
                                     │
                        Enforcer.apply renders state onto:
                        ┌───────────────┬────────────────┬─────────────────┐
                        │  /etc/hosts   │  pf anchor      │  chflags schg    │
                        │  sinkhole     │  block DoH/DoT  │  on all files    │
                        └───────────────┴────────────────┴─────────────────┘
```

- **`BulwarkCore`** — pure, unit-tested logic: domain canonicalization, the
  add/remove/cooldown/passphrase state machine, hosts/pf rendering, PBKDF2
  passphrase hashing. No side effects, so policy is fully testable.
- **`bulwark`** — the control CLI. Enforces the removal gate in code before
  persisting. Mutations need root (to write protected files).
- **`bulwarkd`** — the root LaunchDaemon. Self-heals enforcement and drains due
  removals. `KeepAlive` makes it relaunch if killed.

### The removal gate (the whole point)

| Action | Cost |
|---|---|
| add a site | instant |
| remove a site | queued; stays blocked until `now + cooldown` (default 48h) |
| remove `--now` | instant, but requires the partner passphrase |
| cancel a pending removal | free (re-committing should never be punished) |
| raise the cooldown | free |
| lower the cooldown | requires the partner passphrase |
| set/change passphrase | changing requires the current one |
| `disable` (clean kill) | requires the partner passphrase; keeps blocklist |
| `panic` (break-glass) | always works, no passphrase — but scorched-earth + audit-logged |

### Safety allowlist (anti-footgun)

`add` refuses any domain that is, or is a subdomain of, a protected entry:
built-in Apple/OS endpoints (`apple.com`, `icloud.com`, `cdn-apple.com`, …) plus
any the user marks with `protect` (bank, work). This closes the most likely
self-harm — accidentally sinkholing iCloud/Software Update/your bank and being
stuck behind the cooldown. Built-in protections can't be removed.

### Kill switch philosophy

A frictionless "off" button is just relapse-on-demand, so there isn't one. But a
malfunctioning blocker must never trap you, so `panic` **always** works without a
passphrase — its deterrent is *cost + visibility*, not a lock: it wipes the
entire setup (you rebuild from scratch) and appends a permanent record to the
append-only audit log *before* wiping, so the panic itself is logged and (per the
accountability roadmap) will notify your partner. You're never trapped; you also
can't quietly bail.

The passphrase is stored only as a salted PBKDF2-HMAC-SHA256 hash — the partner
who sets it holds a secret the user never learns.

## Threat model — what stops what

**Defeats casual / impulsive bypass (the common case):**
- Editing `/etc/hosts` → reverted by the watchdog within ~15s; file is `schg`.
- Browser DoH/DoT resolving around hosts → pf anchor blocks known resolver IPs
  and port 853.
- Deleting the CLI / killing the daemon → `KeepAlive` relaunches; enforcement
  lives in root files, not the app.
- Winding the clock **back** to dodge a cooldown → defeated by the monotonic
  clock floor (`max(system_clock, persisted_floor)`).
- Uninstalling on a whim → `uninstall.sh` refuses while sites are blocked,
  routing removal back through the gate.

**Residual holes (documented, not yet closed) — require deliberate effort:**
- A root user can `chflags noschg` and hand-edit files. `schg` is only truly
  immutable at a raised BSD securelevel, which macOS doesn't set by default. It's
  a speed bump, not a wall.
- Winding the clock **forward** past the cooldown still credits the wait (the
  floor moves forward and sticks). Real fix: validate elapsed time against a
  signed remote clock.
- VPNs / proxies tunnel around hosts + pf.
- Booting to Recovery / single-user, or creating a new admin account.
- Using a different device entirely.

The honest closes for those last ones are **not** more local tricks — they are
the roadmap items below (on-device Network Extension, MDM/config-profile
supervision, and accountability reporting).

## Roadmap

Ordered by impact, informed by how the strongest tools in the space work:

1. **Network Extension content filter (`NEFilterDataProvider`)** — a System
   Extension that filters DNS/flows *on-device*. This is the big one: it is
   **immune to DoH/DoT** (it inspects endpoint traffic, not DNS), supports
   domain/wildcard rules natively, and a System Extension requires explicit
   approval to remove. Needs code signing + the
   `com.apple.developer.networking.networkextension` entitlement (you have the
   Apple Developer account). This is how modern, App-Store-viable blockers
   enforce; hosts+pf becomes a fallback layer.
2. **Accountability reporting** — optional channel that emails/pushes a partner
   a summary (attempts, config changes, cooldown requests). The research is
   unanimous that a partner *seeing activity* is the decisive long-term factor.
3. **Signed remote clock** — close the forward-clock hole for cooldowns.
4. **Config profile / supervised-device option** — a partner-controlled
   configuration profile can lock DNS, disable private browsing, block new-user
   creation, and require a password to remove — closing the Recovery/new-account
   holes for users who opt into maximum hardness.
5. **Content-aware detection** — the domain-list arms race never ends; pixel/AI
   detection (à la Canopy/Covenant Eyes) catches social feeds, image boards, and
   AI-chatbot output. Heavy; later.
6. ~~**Menu-bar app**~~ ✅ done — SwiftUI `MenuBarExtra` front end (`BulwarkBar`
   target) over the CLI; mutations go through the macOS admin-auth prompt.

## Prior art studied

- **SelfControl** (open source) — pf anchor + root-owned lock file; the
  canonical macOS enforcement reference. Its known weakness (admin can remove
  the lock file) is exactly the residual hole we document above.
- **Cold Turkey** — the lock-UX gold standard: locked blocks with no cancel
  path, blocks the Settings app to stop clock changes, disables its own
  uninstaller during a lock.
- **Covenant Eyes / Canopy** — accountability + on-device content detection.
- **Tech Lockdown** — best public writing on macOS bypass prevention and its
  limits; their stance ("if someone would wipe the machine, the tool has failed
  — change the strategy") shaped the philosophy here.
