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

**App scale (iOS points, size/line height; updated 2026-11-14 with the app direction, §11):** hero 44/48 Fraunces 500 · display 30/36 Fraunces *italic* 500 (scene statements such as "Tonight is yours, together.") · title 28/34 Fraunces 500 · numeral 40/44 Fraunces 500, tabular figures · numeral-large 64/66 Fraunces 400, tabular figures (the one number a scene is about) · heading 19/25 Instrument Sans 600 · body 17/24 Instrument Sans 400 · callout 15/20 500 · caption 13/18 500 · label 12/16 Instrument Sans 600, uppercase, tracked (small labels over the sky). All Fraunces is set with the SOFT axis at 100, as on the website. Every role scales with Dynamic Type through its text style.

**Website:** the site's type scale lives in its own styles (see W3). The original starting values in web px were hero 48, title 36, numeral 44, heading 20/26, body 17/24, callout 15/20, caption 13/18.

## 5. Shape, space and elevation

Starting values; the designer may redefine shape language, depth and materials.

- Spacing scale: 4, 8, 12, 16, 24, 32, 48.
- Radius (app, updated 2026-11-14): 14 (small controls), 22 (cards), 32 (sheets, panels), pill (buttons, chips, the place bar). The website keeps its own W3 values.
- Shadows: very soft and warm in light theme (`0 1px 2px rgba(42,33,28,.06), 0 8px 24px rgba(42,33,28,.08)`); none in dark theme, use `surface-raised` contrast instead.
- Materials (app): **sky** (full-bleed gradient, §11), **paper** (cream or raised surface with fine grain, a hairline edge and the warm shadow: cards, panels and the quieter pages), **light** (soft translucent discs with a halo: the two people), **glass** (thin translucent material for small chips over the sky).

## 6. Logo direction (pending the name)

Starting idea: **two overlapping circles**, one Hearth and one Glow, where the overlap is the time together. Other concepts that express two people and shared time are welcome. Wordmark in Fraunces. The mark must work as a single-color glyph for the app icon's small sizes and notifications.

## 7. Motion

**Character (fixed):** warm, calm, alive and celebratory. Motion should feel natural and physical, reward connection and never feel frantic, aggressive or punishing.

**Starting guidance (open):** gentle springs and short durations for everyday interactions; longer, richer moments are welcome for celebrations and milestones. A natural association is Glow for celebration, Sage for calm and success, Dusk for protected time; the designer may develop this further.

**App motion (2026-11-14):** quick 0.2 s, standard 0.35 s, gentle 0.45 s springs for controls; **drift** 0.7 s (the lights moving toward or away from each other), **meet** 0.5 s with a little bounce (the lights meeting), **light** 1.0 s ease (the sky changing), celebrations up to 1.2 s, once. With Reduce Motion every one of these becomes a 0.25 s cross-fade and the lights are simply shown in their final place.

**App haptics, one meaning each:** *tick* (a choice changed), *touch* (something answered your finger), *settle* (saved or sent, now at rest), *meet* (the two lights met: an unlock started, pairing completed), *warmth* (three soft rising taps: kudos, a milestone). There is no error or "denied" haptic.

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

## 11. App direction: "Two lights, one evening"

Defined 2026-11-14 under decision B11. It shares its concept with the website's "One evening" (W3): the two circles of the logo are alive.

**The idea.** The app is a scene, not a stack of lists. There is a sky, and in it two lights: **you are Hearth, your partner is Glow**. They are always drawn the same size, with the same treatment and the same amount of information, on every screen: neither is ever the "main" one. Where the lights overlap is the time together. Everything the app celebrates is some version of the two lights drawing closer, meeting or glowing.

**The sky.** Every scene sits under one of three skies, chosen from protected time and the clock, never from decoration:

| Sky | When | Light theme | Dark theme |
|---|---|---|---|
| Daylight | Protected time is more than 90 minutes away (or off) | Cream paper warming toward Glow | A lamplit room: warm near-black |
| Golden hour | The 90 minutes before protected time, and while an unlock is running | Glow-soft to a peach horizon | Candlelight: brown warming to ember |
| Dusk | Protected time | The Dusk color deepening to a warm horizon | The same, a little deeper |

Text placed on a sky uses that sky's own foreground and muted colors, which are tested for WCAG AA against every stop of the gradient in both themes. Dusk is dark in both themes on purpose: protected time should feel like evening whatever the phone's setting. Paper surfaces follow the theme as before.

**Places, not tabs.** Three places, reached from a small floating pill at the bottom (the current place carries the two lights):

- **Tonight**: the home scene. The two lights hold the two balances; the arc above them is protected time (or an unlock) passing, with one large number for the time left; a line for the shared streak; Unlock, the emergency unlock and "Show my code" directly under it; then today's activity on a sheet of paper.
- **Together**: challenges and kudos (earning and giving).
- **Us**: minutes, the week (reports), protected time and paused apps, partner and unpairing, settings.

Every function in `06-ios-app.md` §6 stays reachable. The emergency unlock is one tap from Tonight during protected time and is one of the four ways in the unlock sheet at all times; unpairing is in Us, under the partner, two taps from anywhere.

**Unlocking is a gesture between two people.** Asking your partner, and saying "Go for it" to them, can be done by sliding your light across to meet theirs. The same action is always also an ordinary button directly below, which is what VoiceOver and Switch Control use. When an unlock starts, the lights meet and the sky moves from dusk to golden hour.

**Signature moments (06 §7), all built from the motif:**

| Moment | Treatment | Reduce Motion |
|---|---|---|
| Kudos received | Your partner's light swells and its glow washes over yours while the minutes count up; *warmth* haptic | Glow fades in; the number changes without counting |
| Unlock approved | The lights ease apart to let the evening open, the arc turns to a countdown, the sky warms to golden hour; *meet* haptic | Cross-fade to the new state |
| QR scan success | The two lights slide together and overlap, glowing; *meet* haptic | Lights shown overlapped |
| Streak milestone | The lights settle fully together and a few warm sparks drift up, once | Lights shown together, no sparks moving |
| Minutes expiring timeline | Bars rise from the baseline one day after another, in the person's own color | Bars shown at full height |
| Pairing complete | Two lights carrying the two initials drift together under a dusk sky and settle overlapped; *meet* haptic | Lights shown together |

Never: shaking, red flashes, "denied" sounds or haptics.

**Onboarding is one evening.** It starts in daylight with the lights far apart and ends at dusk with them together; the progress indicator is the two lights drawing closer.

**Accessibility.** Everything the scene shows is also plain text and a VoiceOver label (each balance, the time left as a sentence, the streak). The arc is one element with a spoken description. Layouts are scroll views that reflow up to the accessibility text sizes. Touch targets are at least 44 pt. Red appears only on the two destructive confirmations.

**Apple-controlled surfaces** (the app picker, permission prompts, the pause screen) keep Apple's layout; the pause screen uses the Dusk background, cream text, the Glow button and the two-lights mark as its icon.
