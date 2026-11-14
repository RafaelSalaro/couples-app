# 10 — Brand and design system

## 0. How to read this document

This document separates a small **fixed core** from **starting points**. The designer (Claude Code with Fable 5.2) has full creative freedom in UI and UX for the app and the website, and is encouraged to evolve, extend or replace the starting points when it makes the product better.

| Fixed core (keep) | Starting points (open to reinvention) |
|---|---|
| The philosophy and personality (§1) | Type scale, weights and treatments (§4) |
| Voice and vocabulary rules (§2) | Spacing, radii, elevation, materials (§5) |
| The palette's identity: cream, ink, Hearth, Glow, Sage, Dusk and their roles (§3) | Additional tints, gradients, textures, light effects derived from the palette |
| The two type families, Fraunces and Instrument Sans (§4) | Motion timings and choreography (§7) |
| Accessibility: WCAG AA contrast in both themes, Dynamic Type, VoiceOver, Reduce Motion | Iconography, illustration style (§8–9) |
| Light and dark themes, both first-class | Logo and app icon execution (§6, §10) |

When a starting point changes, update this document so the design system and the docs stay in sync.

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

These hex values are the fixed core of the palette. New tints, gradients, translucency and light effects may be derived from them freely. All text pairings meet WCAG AA (4.5:1) in both themes (checked 2026-11-13: e.g. hearth on surface 5.2:1, ink-muted on surface 5.8:1, on-glow on glow 7.3:1). Partner colors differ in lightness, not only hue, so charts read for color-blind users; also distinguish them with labels or patterns.

## 4. Typography

| Family | Use | Source |
|---|---|---|
| **Fraunces** (soft optical serif) | Headlines, big numbers (minutes, streaks) | Google Fonts (free) |
| **Instrument Sans** | All UI and body text | Google Fonts (free) |

Starting scale, open to refinement (iOS points / web px): hero 44/48 Fraunces 500 · title 30/36 Fraunces 500 · numeral 40/44 Fraunces 500 tabular figures · heading 20/26 Instrument Sans 600 · body 17/24 Instrument Sans 400 · callout 15/20 500 · caption 13/18 500. iOS supports Dynamic Type by mapping these to text styles.

## 5. Shape, space and elevation

Starting values; the designer may redefine shape language, depth and materials.

- Spacing scale: 4, 8, 12, 16, 24, 32, 48.
- Radius: 10 (small controls), 16 (cards), 24 (sheets, large cards), pill (buttons, chips).
- Shadows: very soft and warm in light theme (`0 1px 2px rgba(42,33,28,.06), 0 8px 24px rgba(42,33,28,.08)`); none in dark theme, use `surface-raised` contrast instead.

## 6. Logo direction (pending the name)

Starting idea: **two overlapping circles**, one Hearth and one Glow, where the overlap is the time together. Other concepts that express two people and shared time are welcome. Wordmark in Fraunces. The mark must work as a single-color glyph for the app icon's small sizes and notifications.

## 7. Motion

**Character (fixed):** warm, calm, alive and celebratory. Motion should feel natural and physical, reward connection and never feel frantic, aggressive or punishing.

**Starting guidance (open):** gentle springs and short durations for everyday interactions; longer, richer moments are welcome for celebrations and milestones. A natural association is Glow for celebration, Sage for calm and success, Dusk for protected time; the designer may develop this further.

**Fixed rules:**
- Never shake, flash red or play "denied" sounds.
- Reduce Motion: every animated moment has a calm equivalent (for example fades) with no information lost.
- **Website:** the marketing site may be more expressive than the app (scroll-driven storytelling, transitions, depth and light effects) as long as it keeps the same warm, calm character. See `09-website-and-seo.md` §10.

## 8. Iconography

Starting point: SF Symbols on iOS and Lucide on the web and Android. Custom icons, animated symbols or a bespoke icon set are welcome if they fit the brand.

## 9. Imagery

Real moments: hands, shared meals, walks, warm evening light, laughter. People present with each other. Never stock photos of couples staring at phones, never phones as villains. Illustration style is open; it should feel warm and human and use the brand palette.

## 10. App icon direction

Starting idea: cream or Dusk background with the brand motif in Hearth and Glow. The designer may explore other directions. Fixed: it must read clearly at the smallest sizes and on light, dark and tinted home screens.
