# 10 — Brand and design system

## 1. Personality

Warm, calm, playful, equal. It should feel like an evening at home together, not a lock screen. Every surface answers "is this controlling?" with a clear no.

## 2. Voice and vocabulary

| Instead of | Use |
|---|---|
| Block, blocked | Pause, protected time |
| Ask for permission | Ask your partner |
| Approve / Deny | Go for it / Let's wait |
| Penalty, failed, violation | Missed day, new streak starts today |
| Points | Minutes |
| Admin, owner | (never; both are partners) |
| Addiction (in-app) | Habit, scrolling (marketing may say "dopamine" carefully; no medical claims) |

Rules: short sentences, second person, never guilt. Celebrate effort. Use the partner's name ("Ask Ana") wherever possible.

## 3. Color

| Token | Light | Dark | Use |
|---|---|---|---|
| `surface` | #FBF6F0 | #191513 | Page and app background (cream) |
| `surface-raised` | #FFFFFF | #231E1B | Cards, sheets |
| `surface-sunken` | #F2E9DE | #120F0D | Wells, grouped backgrounds |
| `line` | #E5D8C8 | #3A322C | Hairlines, input borders |
| `ink` | #2A211C | #F4EDE5 | Primary text |
| `ink-muted` | #6B5E55 | #B6A99E | Secondary text |
| `hearth` | #AD472E | #E8836A | Primary actions, brand warmth, Partner A |
| `hearth-soft` | #F9E4DB | #4A2820 | Tinted backgrounds behind hearth text |
| `on-hearth` | #FFFFFF | #191513 | Text on hearth fills |
| `glow` | #E9A23B | #F2B65A | Earned minutes, kudos, celebrations, Partner B (fill only) |
| `glow-strong` | #8F5A0F | #F2B65A | Glow as text on surfaces |
| `glow-soft` | #FCEBCB | #45351A | Tinted backgrounds for minutes/kudos |
| `on-glow` | #2A211C | #191513 | Text on glow fills |
| `sage` | #4A6E53 | #8DB596 | Protected time, streaks, success |
| `sage-soft` | #E1EBDF | #22332A | Tinted backgrounds for sage text |
| `on-sage` | #FFFFFF | #191513 | Text on sage fills |
| `dusk` | #2C2430 | #2A2230 | Pause screen, night moments |
| `on-dusk` | #F5EEE6 | #F5EEE6 | Text on dusk |
| `danger` | #A8322A | #F0A097 | Destructive actions only (delete account, confirm unpair) |
| `partner-a` | alias `hearth` | | Charts: the user |
| `partner-b` | alias `glow` | | Charts: the partner |

All text pairings meet WCAG AA (4.5:1) in both themes (checked 2026-11-13: e.g. hearth on surface 5.2:1, ink-muted on surface 5.8:1, on-glow on glow 7.3:1). Partner colors differ in lightness, not only hue, so charts read for color-blind users; also distinguish them with labels or patterns.

## 4. Typography

| Family | Use | Source |
|---|---|---|
| **Fraunces** (soft optical serif) | Headlines, big numbers (minutes, streaks) | Google Fonts (free) |
| **Instrument Sans** | All UI and body text | Google Fonts (free) |

Scale (iOS points / web px): hero 44/48 Fraunces 500 · title 30/36 Fraunces 500 · numeral 40/44 Fraunces 500 tabular figures · heading 20/26 Instrument Sans 600 · body 17/24 Instrument Sans 400 · callout 15/20 500 · caption 13/18 500. iOS supports Dynamic Type by mapping these to text styles.

## 5. Shape, space and elevation

- Spacing scale: 4, 8, 12, 16, 24, 32, 48.
- Radius: 10 (small controls), 16 (cards), 24 (sheets, large cards), pill (buttons, chips).
- Shadows: very soft and warm in light theme (`0 1px 2px rgba(42,33,28,.06), 0 8px 24px rgba(42,33,28,.08)`); none in dark theme, use `surface-raised` contrast instead.

## 6. Logo direction (pending the name)

Motif: **two overlapping circles**, one Hearth and one Glow, where the overlap is the time together. Wordmark in Fraunces. The mark must work as a single-color glyph for the app icon's small sizes and notifications.

## 7. Motion

- Gentle springs, 200–450 ms; ease-out for entrances; nothing longer than 600 ms except celebrations (≤ 1.2 s, once).
- Celebration moments use Glow; calm states use Sage; protected time uses Dusk.
- Never shake, flash red or play "denied" sounds.
- Reduce Motion: replace movement with opacity fades.
- **Website:** the marketing site may be more expressive than the app (scroll-driven storytelling, transitions, depth and light effects) as long as it keeps the same warm, calm character. See `09-website-and-seo.md` §10.

## 8. Iconography

SF Symbols (rounded variants where available) on iOS; Lucide on the web and Android, 1.75 px stroke, rounded caps. Icons inherit text color.

## 9. Imagery

Real moments: hands, shared meals, walks, warm evening light, laughter. People present with each other. Never stock photos of couples staring at phones, never phones as villains. Illustrations, if used, are flat shapes from the circle motif in brand colors.

## 10. App icon direction

Cream or Dusk background, the two overlapping circles in Hearth and Glow. Test at 29 pt and on both light and dark home screens.
