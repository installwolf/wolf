# DESIGN.md — Wolf brand surface

## Strategy

- **Register:** brand. **Theme:** dark (the 1 a.m. scene forces it).
- **Color strategy:** Committed. A single ember/wolf-eye amber carries the brand
  across a forest-night near-black. Reference: "amber wolf-eyes in a black pine
  forest at night."

## Color (OKLCH)

- `--night`      `oklch(0.15 0.012 240)`  page base, cold near-black (faint blue)
- `--night-2`    `oklch(0.185 0.014 240)` raised panels / sections
- `--night-3`    `oklch(0.23 0.016 240)`  hairlines, borders (use full borders)
- `--bone`       `oklch(0.95 0.008 90)`   primary text, warm off-white
- `--ash`        `oklch(0.72 0.012 240)`  secondary text
- `--ember`      `oklch(0.78 0.16 68)`    THE accent: CTAs, wolf-eyes, key figures
- `--ember-deep` `oklch(0.62 0.15 55)`    ember hover / gradients
- `--moon`       `oklch(0.86 0.04 230)`   rare cold highlight, used sparingly
- `--danger`     `oklch(0.62 0.17 25)`    only for the honesty/limits callouts

Never `#000`/`#fff`. Ember is Committed: used generously, not capped at 10%.

## Typography

Voice words: feral, unbreakable, disciplined.

- **Display / headings:** Bricolage Grotesque (700–800). Characterful, raw-but-
  modern grotesque; carries big fierce statements. Not on the reflex-reject list.
- **Body / UI:** Hanken Grotesk (400–600). Clean, slightly warm, serious.
- **Mono (terminal snippets only):** JetBrains Mono. Justified: these are literal
  `wolf` CLI commands, not decorative "tech" costume.
- Fluid `clamp()` headings, ≥1.25 step ratio. Hero can go enormous.
- Dark bg → +0.05–0.1 line-height on light text.

## Layout

- Left-aligned, asymmetric. No centered icon-title-subtitle card stacks.
- Long single-column-ish scroll with distinct section worlds; vary spacing with
  `clamp()` for rhythm.
- Pricing tiers are two *distinct* objects (Lone Wolf vs The Pack), not identical
  cards. The Pack is the emphasized one.

## Imagery / motif

- Hero is a crafted **canvas nocturne**: drifting fog + faint snow particles +
  amber wolf-eye glints emerging from the dark. Real scene, not a colored block.
- Motif reused subtly: ember eye-glints, a thin "chain/binding" divider (the
  Gleipnir idea), amber focus rings.

## Motion

- One orchestrated hero load: fog settles, eyes open (fade/scale), headline
  staggers in. Ease-out-expo, no bounce. Respect `prefers-reduced-motion`.
- Section reveals via IntersectionObserver (opacity + small translate only).
- Never animate layout props.

## Components

- Buttons: solid ember primary (night text), ghost secondary (ember hairline).
- Terminal card: night-2 panel, mono, a real `wolf` session; amber prompt glyph.
- Honesty callout: full border in `--danger`, not a side-stripe.
