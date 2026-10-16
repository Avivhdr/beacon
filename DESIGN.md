---
name: Beacon
direction: cockpit instrument panel. Dark, clean, one signal color.
colors:
  ink: "#0C0F14"         # panel background, page background
  surface: "#12161D"     # top of the panel gradient, bars, raised areas
  raised: "#1A2029"      # hover fill behind small controls
  hairline: "rgba(255,255,255,0.07)"
  hairlineStrong: "rgba(255,255,255,0.14)"
  text: "#E6EAF0"
  dim: "#8A93A3"
  faint: "#525B6A"
  amber: "#F4A93B"       # the one signal color: selection, mentions, stale, the radar beam
  red: "#F0575D"         # status only: failing CI, changes requested, errors
  green: "#41D18A"       # status only: passing CI, approved, link OK
  steel: "#9FB2CC"       # neutral event kinds: reply, comment, review
type:
  numerals: "SF Pro, 58pt, ultraLight, tabular digits"
  readout: "SF Mono, 8.5-11pt, semibold, UPPERCASE, tracking 1.2-3"
  title: "SF Pro, 13.5pt, medium"
  body: "SF Pro, 12-12.5pt, regular"
  meta: "SF Mono, 10.5pt, regular"
radius:
  panel: 14
  lamp: 6
  pill: 6
  tag: 3
motion:
  arrive: "cubic-bezier(0.22, 1, 0.36, 1), 0.38-0.5s"
  leave: "cubic-bezier(0.5, 0, 0.75, 0), 0.14-0.22s"
  stagger: "35ms per row, first 9 rows only"
---

# Beacon design

Beacon looks like an instrument panel on a spacecraft: blue-black ink, cool white type, thin rules, and one amber signal color. It's dark and quiet, and the only things that light up are the things that need you.

The source of truth for the app is `Sources/Beacon/Theme.swift` (palette, readout text, lamps, tick ruler, motion curves) and `PanelView.swift`. The website must use the same tokens as the frontmatter above.

## Rules

1. **One signal color.** Amber marks what's selected or what wants attention. Red and green only ever mean status (failing or passing, changes requested or approved). Never use them for decoration.
2. **Numbers are the hero.** Counts are huge and ultra-light. Labels next to them are tiny uppercase mono readouts. Keep that contrast: 58pt numerals beside 9.5pt labels.
3. **Readouts talk like instruments.** Uppercase monospace with wide tracking for labels, status and section headers ("SYNCED 40S AGO", "QUEUE EMPTY", "ALL CLEAR"). Body text stays in normal sentence case.
4. **Hairlines, not boxes.** Sections are split by 1px rules at 7-14% white, not cards. No drop shadows inside the panel, no glassmorphism, no gradients on text.
5. **Lamps carry state.** A 24pt square with a 6pt radius, dark housing, colored glyph, colored 14% fill and 35% stroke when lit. Unlit lamps are grey. State is always shape plus color, never color alone.
6. **Motion means something changed.** Things arrive with ease-out-quint and leave faster. Counters roll up from zero when the panel opens. Rows cascade in. The radar sweep only runs on empty states. Everything respects Reduce Motion.

## Components

- **Status strip.** A 6pt status dot (green OK, pulsing amber while syncing, red on error) and a mono readout of the last sync. Chrome icon buttons on the right.
- **Readout tabs.** A small dot plus an uppercase label above a huge numeral. The selected tab is amber, with a 36x2 amber bar under it that slides between tabs.
- **Tick ruler.** Ticks every 6pt, a long tick every fifth, 6-13% white. It sits under the header like a scale.
- **Ruled header.** An uppercase readout, an optional count chip (amber with ink text when above zero), then a hairline to the edge.
- **Pill button.** Uppercase mono text, a 6pt radius and a hairline border. On hover it turns amber with an 8% amber fill.
- **Status tag.** An 8pt uppercase mono label in a 3pt radius box, tinted with its status color.
- **Radar.** Four rings, a crosshair, bearing ticks, and an amber beam with a fading trail. Used only for "all clear" and "scanning".

## Voice

Short and plain. "All clear", "Nothing needs you right now", "Queue empty", "Nothing in flight". Empty states vary their line so they stay fresh. No exclamation marks and no emoji.

## Website mapping

- Page background `ink`, content on `surface` where it needs separation, hairlines for structure.
- Type: the system stack (`-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif`) for prose, and `ui-monospace, "SF Mono", Menlo, monospace` for readouts. Don't load Inter or other web fonts. On a Mac the site should feel like the app.
- Big numerals at `font-weight: 200` or lower, `font-variant-numeric: tabular-nums`.
- The hero shows the real panel, as a screenshot from the snapshot tool or a faithful HTML rebuild, with the radar sweep drawn on a canvas.
- Honor `prefers-reduced-motion` and keep text contrast at WCAG AA or better on `ink`.
