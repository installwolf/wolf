# Wolf — Competitive Positioning

Where Wolf fits in the porn/compulsive-use blocking landscape, and — in the same
honest spirit as [DESIGN.md](DESIGN.md) — where the alternatives are genuinely
better than Wolf today.

This is a living document. The tools below are what the recovery communities
(r/pornfree, r/NoFap, and adjacent) actually recommend as of 2026, grouped by the
job they do.

## The landscape, by category

The space is not one market — it's four, and most people end up stacking two or
three. Wolf lives squarely in the first.

| Category | Representative tools | Core mechanism | What it's good at |
|---|---|---|---|
| **Self-binding / friction blockers** | **Wolf**, [SelfControl](https://selfcontrolapp.com), [Cold Turkey](https://getcoldturkey.com), [Freedom](https://freedom.to) | Lock *yourself* out; make undoing hard | Beating the moment of weakness |
| **Accountability / monitoring** | [Covenant Eyes](https://covenanteyes.com), [Ever Accountable](https://everaccountable.com) | A human ally *sees your activity* (reports/screenshots) | Long-term change, removing secrecy |
| **AI real-time content filters** | [Canopy](https://canopy.us), Bulldog, BlockerX | On-device detection of *unknown* explicit images/video | Catching new sites, social feeds, search |
| **DNS-level filters** | [NextDNS](https://nextdns.io), [CleanBrowsing](https://cleanbrowsing.org), Control D, [Pi-hole](https://pi-hole.net) | Filter resolution network-wide | Covering every device at once |

## Feature comparison — the self-binding peer set

This is Wolf's true peer group. The accountability, AI-filter, and DNS tools are
complements, not direct substitutes (see below).

| | **Wolf** | SelfControl | Cold Turkey | Freedom |
|---|:---:|:---:|:---:|:---:|
| Price | **Free** | Free | Freemium (paid Pro) | Subscription |
| Open source | **Yes** | Yes | No | No |
| Runs fully local / no cloud account | **Yes** | Yes | Yes | No (account) |
| Persistent blocklist (not just a timer) | **Yes** | No (timer only) | Yes | Yes |
| Instant to add, hard to remove (asymmetry) | **Yes** | Timer only | Locked mode | Locked mode |
| Human holds the removal key | **Yes** (partner passphrase) | No | No (random string) | No |
| Self-healing against tampering | **Yes** (root watchdog, 15s) | Partial | Partial | Partial |
| Blocks known DoH/DoT resolvers | **Yes** (pf anchor) | No | No | No |
| Cross-device (phone) | No | No | Windows/Mac | Yes |
| Activity reporting to a partner | No (roadmap) | No | No | No |
| Content/AI filtering of unknown pages | No | No | No | No |

## Where Wolf wins

Against its real peers, Wolf's differentiation is specific and defensible:

- **Persistent, not a timer.** SelfControl blocks for *N* hours and then it's
  gone — built for focus sessions, not a permanent quit. Wolf stays blocked until
  you *deliberately* remove it. That's the right model for the actual goal.
- **A human holds the key.** Cold Turkey's lock is a random string you can
  regenerate; SelfControl has no human at all. Wolf's partner-passphrase gate puts
  the removal key in *someone else's hands* — a lightweight fusion of friction and
  accountability no free tool offers.
- **Free, open, local, private.** Every accountability tool worth using is a
  subscription that uploads your browsing or screenshots to a company. For a
  category this sensitive, "runs entirely on your machine, nothing leaves, the
  code is auditable" is a real trust wedge — and it's unique here.
- **Stronger tamper-resistance than SelfControl** — root watchdog self-heal,
  `chflags schg` immutability, and pf blocking of known DoH/DoT resolvers (see
  [DESIGN.md](DESIGN.md#threat-model--what-stops-what)).

**Net:** for a technical person on a Mac who wants a *free, private, self-binding*
blocker, Wolf is arguably the best option available — clearly better than
SelfControl (persistent vs. timer) and competitive with paid Cold Turkey.

## Where the alternatives are honestly better

Being honest about limits is the brand. Four real gaps:

1. **Accountability beats blocking — and Wolf doesn't do it yet.** Community and
   research consensus agree: a human who *sees your activity* drives long-term
   change; blocking alone is a speed bump. Covenant Eyes / Ever Accountable win on
   the metric that matters most. Wolf's partner only *holds a key* — they never
   learn whether you relapsed on another device or via a Recovery boot. This is the
   single biggest gap, and it's exactly what the accountability-reporting roadmap
   item exists to close.
2. **Mobile is where relapse happens now — Wolf is Mac-only.** A locked-down Mac
   with an unblocked phone in your pocket is a large hole, and the communities say
   so repeatedly. Covenant Eyes, Canopy, and BlockerX are cross-device.
3. **Domain blocklists are whack-a-mole; AI filters aren't.** Canopy blocks
   *new/unknown* explicit content and images inside feeds, search, and image
   boards. Wolf only blocks domains already on a list — new sites and social leak
   straight through.
4. **Bypass ceiling equals SelfControl's.** Admin + Recovery boot defeats it. Wolf
   is honest about this; it means Wolf is better-*designed* around the limit, not
   past it.

## The confession is part of the mechanism

There's a force in the accountability model that the feature comparison above
doesn't capture, because it happens *before* any activity is ever reported: to
enroll a partner, you have to **tell a specific, named human that you have a
problem you can't hold alone.**

Recovery orthodoxy treats that admission as the intervention, not the prelude to
it. Compulsive use runs on secrecy; the act of saying it out loud to someone
whose opinion you care about does therapeutic work before that partner sees a
single event. "Removing secrecy" is listed as the accountability category's core
good above — but the disclosure precedes the visibility, and it's the half the
incumbents can't productize. Covenant Eyes can *show* your partner your activity;
it can't manufacture the moment you decide to have one.

This cuts both ways, and honesty is the brand:

- **It's a differentiator, not a tax — for the user who's ready.** A self-held
  passphrase you type yourself is a note to your future self. Handing the key to
  someone you'd be ashamed to relapse in front of is a categorically different
  commitment, and it's one SelfControl and Cold Turkey structurally cannot offer.
- **But it's also Wolf's steepest adoption cliff.** Wolf's wedge is *free, local,
  private, no account* — which attracts precisely the person not yet ready to tell
  anyone. Requiring a willing, informed partner at the front door is a wall for
  exactly the user the rest of the product is built to reach. The design
  implication (keep the solo on-ramp; make the partner a *graduation step*) lives
  in the [accountability RFC](docs/accountability-partner.md#disclosure-as-mechanism--and-as-adoption-cost).

## What Wolf deliberately does *not* try to be

- **Not a monitoring product.** Wolf holds no activity data by design. When
  accountability arrives it is planned as an *opt-in, end-to-end* channel — never a
  company-side screenshot archive of the most sensitive data a person has.
- **Not an "off button" vendor.** A frictionless disable is relapse-on-demand.
  `panic` exists only so a malfunction can't trap you, and it's scorched-earth +
  audit-logged (see [DESIGN.md](DESIGN.md#kill-switch-philosophy)).
- **Not claiming to be unbypassable.** The strongest local claim we make is
  "slow, effortful, and visible." The genuine hardening (on-device Network
  Extension, config-profile supervision, accountability) is on the
  [roadmap](DESIGN.md#roadmap), not marketing copy.

## Reading the roadmap through this lens

The gaps above map directly onto the [DESIGN.md roadmap](DESIGN.md#roadmap), in
the order that closes the most valuable gaps first:

- **Accountability reporting** closes gap #1 — the highest-value gap, since
  accountability out-performs blocking for durable change.
- **Cross-device / mobile coverage** closes gap #2 — arguably matters more in
  practice than deeper Mac-side enforcement, because an unblocked phone undercuts
  the entire value proposition.
- **Network Extension content filter** hardens the bypass ceiling (gap #4) and is
  the path to DoH/DoT immunity.
- **Content-aware detection** eventually closes gap #3 (the blocklist arms race).

None of this changes what Wolf is: the free, open, local, self-binding core. The
roadmap is about making the *human-in-the-loop* half as strong as the friction
half already is.
