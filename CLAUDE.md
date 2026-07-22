# Umbra

Flutter app, launching in Dubai. This file is the design and engineering
constitution for the project — read it before writing UI code. It exists
because visual quality erodes fast across a codebase unless the rules are
written down once and enforced everywhere, not re-decided screen by screen.

**Status:** design system defined below; product surface (screens, flows,
data model) is not yet documented here — fill that in as it's decided. Don't
invent product features to fill this gap.

## Design philosophy

Umbra is a luxury product. Luxury in software is not decoration — it's
restraint. Concretely:

- **Negative space is a feature.** Generous padding and fewer elements per
  screen read as expensive; density reads as cheap. When in doubt, remove an
  element rather than shrink it.
- **One accent, used sparingly.** Gold means something precisely because it
  isn't everywhere. If every icon and label is gold, none of them are.
- **Motion is quiet.** Every interactive element responds to touch (nothing
  feels inert), but nothing bounces, spins, or calls attention to itself
  unprompted. Confidence, not enthusiasm.
- **Consistency over cleverness.** A card's internal layout must look the
  same whether its content is one line or four. A button must feel the same
  everywhere it appears. Bespoke one-off treatments are the fastest way to
  make an app feel cheap — see "Component principles" below.

## Visual identity

### Color

Dark-first, near-black base with a single restrained gold accent. Do not
introduce a light theme unless the product explicitly needs one — a
luxury-black app that half-heartedly supports light mode usually looks worse
in both, and Dubai's own luxury-app peer set (hospitality, private banking,
concierge apps) skews dark-first for exactly this reason.

Never hardcode a `Color(0x...)` in a widget. Every color used in a widget
comes from `AppColors` (or the `ColorScheme` derived from it) — see
"Design tokens."

```
// ── Background ────────────────────────────────────────────────────────────
bgVoid            #000000   True black. Screen background, OLED-true.
bgSurface         #0E0E10   Cards, sheets — one step off void.
bgSurfaceRaised   #17161A   Modals, popovers — one step above bgSurface.
bgHairline        #232226   Dividers, input borders, card outlines (use at
                             low opacity over bgSurface, not as a flat fill).

// ── Gold accent — spend it deliberately ────────────────────────────────────
gold              #C9A227   Primary accent. Icons, active states, key CTAs,
                             the one thing on a screen you want the eye to
                             land on first.
goldMuted         #8C6D1F   Pressed/disabled gold, secondary emphasis.
champagne         #E8D9A0   Rare — large celebratory moments only (a
                             completed purchase, a milestone). Using this for
                             routine UI drains its impact.
goldGlow          gold @ 14% opacity   Soft glow behind an active/selected
                             element. Never a hard drop shadow in this color.

// ── Text — warm off-white, not pure white ──────────────────────────────────
textPrimary       #F5F1E8   Body text, headlines. Warm ivory ties to gold;
                             pure #FFFFFF reads cold against true black.
textSecondary     textPrimary @ 70%
textMuted         textPrimary @ 45%
textOnGold        #16140C   Text/icons placed ON a solid gold fill.

// ── Status — jewel tones, not Material defaults ─────────────────────────────
success           #4E9F6E   Emerald, not lime green.
warning           gold      Warning and "attention" states reuse the accent
                             at full strength — do not add a second yellow.
error             #C0453F   Deep ruby, not fire-engine red.
```

**Contrast is not optional.** Gold-on-black at small text sizes will fail
WCAG AA — check every pairing:

- Body/label text → always `textPrimary` or `textSecondary`, never raw
  `gold`, no matter how on-brand it looks in a mock. Gold is for icons, thin
  rules, large numerals, and short high-emphasis labels (≥ 18sp / bold), not
  paragraphs.
- Run every new color pairing through a contrast checker against its actual
  background before shipping it, not just against `bgVoid` — surfaces stack
  (`bgSurface` on `bgVoid`, `bgSurfaceRaised` on `bgSurface`), and a pairing
  that passes on one fails on another.

### Typography

Pair a refined Arabic face with a refined Latin face at matching weight and
x-height — mismatched pairings (a delicate Latin serif next to a heavy
generic Arabic sans) is the single most common way a bilingual luxury app
looks unfinished. Recommended starting point (both free, both on Google
Fonts, confirm final choice with whoever owns the brand):

| Role | Latin | Arabic |
|---|---|---|
| Display / headlines | Fraunces or Canela (license-permitting) | Amiri — classical Naskh, genuinely elegant at display size |
| Body / UI | Inter or General Sans | IBM Plex Sans Arabic or Almarai — legible at small sizes, has the weight range Amiri lacks |

Do not use the display face below ~20sp — Amiri in particular loses
legibility fast at body sizes. Body copy is always the UI face, in both
languages.

Type scale, spacing, and weights live in `AppTypography`, not inline
`TextStyle(...)` calls — see "Design tokens."

## Design tokens

Mirror this structure (this exact split — one file per concern, static
const fields, private constructor) — it's a proven pattern, not a proposal:

```
lib/core/constants/
  app_colors.dart       // palette above, grouped by semantic role
  app_typography.dart   // TextStyle per scale step (displayL, titleM, bodyM, labelS...)
  app_theme.dart         // spacing, radius, icon size, shadow, motion-duration tokens
  app_icons.dart         // one IconData constant per icon used anywhere in the app
```

Rules, all non-negotiable:

- **No magic numbers.** Every padding, gap, radius, icon size, and duration
  in a widget is a named constant from `AppTheme`, not a raw double.
- **One icon set.** Every icon referenced through `AppIcons.xxx`, never
  `Icons.xxx` inline — this is what makes a future icon-set swap or RTL
  icon-mirroring fix (see Localization) a one-file change instead of a
  grep-and-replace across the app.
- **Spacing scale**, 4pt base: `xs 4 · s 8 · m 12 · l 16 · xl 20 · xxl 24 ·
  xxxl 32`. Screen horizontal padding is one constant used everywhere
  (`screenPaddingH`), not re-decided per screen.
- **Motion durations** are tokens, not inline `Duration(milliseconds: N)`:
  `xs 150 · fast 200 · normal 300 · slow 500`. Keep it to these four unless
  there's a specific reason not to — a codebase with eleven slightly
  different animation durations feels inconsistent even when no single
  screen looks wrong in isolation.

## Component principles

Every reusable visual pattern (card, button, chip, badge, list row, empty
state, loading state) is a shared widget, built once, used everywhere.
Specific rules learned the hard way on this team's other admin-facing work
— apply them here too:

- **Cards align regardless of content length.** A grid of cards where card 1
  has a one-line description and card 2 has three lines must still have
  every card's footer/action row land at the same y-position. Use a
  `Column` with the footer pinned via `Spacer()`/`MainAxisAlignment
  .spaceBetween` inside a fixed- or intrinsic-height card, and clamp
  description text with `maxLines` + `overflow: TextOverflow.ellipsis`
  rather than letting it grow unbounded. Never ship a grid where rows
  visibly zigzag because content length wasn't accounted for.
- **Status/category chips are tinted, not solid.** A chip's fill is its
  semantic color at ~12% opacity with the full-strength color as the text —
  never a saturated solid fill as the default state. Solid fills are for
  primary CTAs only, one or two per screen, maximum.
- **Every tappable thing gives tactile feedback.** No bare `GestureDetector`
  or `InkWell` with no visual response. Build (or port) a `PressableScale`
  wrapper — scale to ~0.97 on press-down, spring back on release, `animXS`
  duration — and use it on every row, pill, icon button, and card. This is
  the single highest-leverage thing for making the app feel "designed" vs.
  "assembled."
- **Empty and loading states are designed, not default.** No bare spinner
  centered on a blank screen, no plain "No items" text. Every list/grid
  needs a considered empty state (icon + one line of copy, in the brand
  voice) and a skeleton-shaped loading state that matches the real
  content's layout — not a generic spinner — so the screen doesn't visibly
  "pop" into its final shape.
- **Destructive actions confirm proportionally to their severity.** A quick
  one-tap confirm sheet for reversible actions; a typed-confirmation step
  (re-enter a name/value) for anything irreversible or high-value —
  deleting an account, cancelling a paid booking, etc.
- **Copy is short and specific.** No filler ("Oops! Something went wrong")
  where a real sentence tells the user what happened and what to do next.

## Motion & micro-interactions

- Page transitions: a restrained custom transition (shared-axis fade +
  slight scale, or a fade-through) — not the default platform slide on both
  iOS and Android. Pick one transition and use it everywhere; don't mix
  platform-default transitions with custom ones.
- Respect `MediaQuery.disableAnimations` — every custom animation should
  have a near-zero-duration fallback when the user has reduced motion
  enabled at the OS level. This is an actual accessibility requirement, not
  a nice-to-have.
- Haptics: a light `HapticFeedback.selectionClick()` on meaningful taps
  (selecting an option, completing an action) — used sparingly, not on
  every single tap in the app, or it stops meaning anything.
- No animation exists purely for delight with no functional purpose (state
  change, progress, confirmation). If you can't say what state change an
  animation communicates, cut it.

## Localization — Dubai / UAE

Bilingual from day one: **Arabic (primary for the market) and English**,
using Flutter's `flutter_localizations` + `intl`, not a hand-rolled string
map. Every user-facing string goes through localization from the first
screen built — retrofitting i18n after screens are hardcoded in English is
far more expensive than doing it from the start.

- **RTL is a first-class layout direction, not a mirror-image afterthought.**
  Use `EdgeInsetsDirectional`, `AlignmentDirectional`, and `Directionality`-
  aware widgets (`Row` respects `TextDirection` automatically; avoid
  `Positioned(left: ...)`/`right: ...` in favor of `start`/`end`) throughout.
  Test every screen in RTL as you build it, not as a pass at the end.
- **Not everything flips.** Directional icons (back chevrons, forward
  arrows, send/reply icons) mirror in RTL. Icons representing a real-world
  object with an inherent orientation (a play button, a logo, a clock face,
  a photo) do **not** mirror. Get this wrong and it reads as broken, not
  stylistic — check each icon deliberately rather than blanket-mirroring
  the icon set.
- **Numerals:** default to Western Arabic numerals (0–9) even within Arabic
  text — this is the prevailing convention in UAE consumer apps (banking,
  government services, delivery apps), not Eastern Arabic-Indic numerals.
  Confirm with the brand if they want the more traditional Eastern numerals
  for a specific luxury-heritage effect, but don't assume it.
- **Currency:** AED, formatted via `intl`'s `NumberFormat.currency`, not
  string-concatenated — get grouping and decimal conventions from the
  locale rather than hardcoding "AED 1,234.00".
- **Dates:** Gregorian calendar for all functional/transactional dates
  (bookings, receipts, timestamps) — that's the UAE business-day standard.
  A Hijri calendar toggle is a reasonable premium/cultural touch for
  display contexts (a greeting, a cultural event reference) but should
  never be the only date system for anything time-sensitive.
- **Cultural design notes:** Friday–Saturday is the UAE weekend (not
  Saturday–Sunday) — any "this week"/business-day logic must use the local
  week definition, not assume a Western week. Ramadan/Eid awareness (hours,
  promotions, greetings) is worth a content hook if the product has any
  seasonal or scheduling surface.
- Arabic UI text tends to run 20–30% longer than the English equivalent for
  the same meaning — design text containers with that slack in mind rather
  than tightly fitting English strings and having Arabic overflow/wrap
  awkwardly.

## Accessibility

- Every interactive element has a minimum 44×44 logical-pixel tap target,
  even if its visual size is smaller (pad the tap area, don't grow the
  icon).
- Every image/icon-only button has a `Semantics` label — screen reader
  support isn't optional for a launch-market app.
- Don't communicate state by color alone (a gold vs. muted-gold chip is not
  enough on its own) — pair with an icon or text label too, for users with
  color-vision differences and for the RTL/translated screen-reader
  experience alike.

## Engineering conventions

- No comments explaining *what* code does — name things well instead.
  Comment only the non-obvious *why* (a workaround, a business-rule
  constraint, a deliberate deviation from a pattern above).
- State management, folder structure, and package choices: decide once,
  document the decision here when made, and don't let a second pattern
  creep in alongside it. Consistency of *approach* matters as much as
  consistency of *visuals*.
- Before adding a new color, spacing value, or duration anywhere: check
  whether an existing token in `AppColors`/`AppTheme` already covers it.
  Extend the token set deliberately; don't reach for a one-off value
  because it's faster in the moment.

## Design QA checklist

Run through this before calling any screen done:

- [ ] Every color traces to an `AppColors` token; no inline `Color(0x...)`.
- [ ] Every spacing/radius/icon-size traces to `AppTheme`; no magic numbers.
- [ ] Cards/rows align consistently across varying content lengths.
- [ ] Every tappable element has press feedback.
- [ ] Loading and empty states are designed, not default.
- [ ] Screen tested in both English (LTR) and Arabic (RTL).
- [ ] Text containers have room for ~25% Arabic text expansion.
- [ ] Directional icons mirror in RTL; object icons don't.
- [ ] All text-on-background pairings pass WCAG AA contrast.
- [ ] Reduced-motion setting respected.
