# Couples App — Project Documentation

**Working title:** "Couples App" (final name not chosen — front-runners: *Linger*, *Our Hours*, *Fica*).
**Status:** Planning complete, nothing implemented yet.
**Last reviewed:** 2026-11-13 (covers every decision made in planning conversations from 2026-11-10 onward).

This folder is the single source of truth for building the app, the website and the business around it. It is written so Claude Code can build from it later without needing the original conversations.

## How to use these documents

1. These docs live in the repository at github.com/RafaelSalaro/couples-app (`docs/`, with `CLAUDE.md` at the root), mirrored in the claude.ai Project "Couples app".
2. Claude Code reads `CLAUDE.md` automatically when it opens the repository. That file tells it which document to read for which task.
3. Build in the order given in `12-implementation-plan.md`. Each work package lists the documents it depends on and its acceptance criteria.
4. When a decision changes, update `02-decisions-log.md` first, then the affected document.

## The documents

| # | File | What it covers |
|---|---|---|
| — | `CLAUDE.md` | Rules for Claude Code: principles, stack, conventions, what never to do |
| 01 | `01-product-vision.md` | What the app is, who it is for, the central philosophy, positioning |
| 02 | `02-decisions-log.md` | Every decision with its status (decided, assumed, open) and the verified technical facts behind it |
| 03 | `03-feature-spec.md` | The complete functional specification and every rule of the minutes economy |
| 04 | `04-architecture.md` | System architecture, components, data flows, security and privacy |
| 05 | `05-data-model-and-api.md` | Database schema, row-level security, server functions, API contracts |
| 06 | `06-ios-app.md` | iPhone app: targets, Apple frameworks, screens, animations, entitlements |
| 07 | `07-testing-plan.md` | Unit, integration, device and beta testing; App Review package |
| 08 | `08-android-app.md` | Android app (after the iPhone app is great): approach, policy risks, parity |
| 09 | `09-website-and-seo.md` | Marketing website, waitlist, technical SEO, weekly SEO routine |
| 10 | `10-brand-and-design-system.md` | Brand identity, colors, type, motion, voice, imagery |
| 11 | `11-business-legal-launch.md` | LLC, store accounts, pricing, costs, legal pages, launch and growth |
| 12 | `12-implementation-plan.md` | Phased plan, the credit-window sprint, ordered Claude Code work packages |
| 13 | `13-risks-and-open-questions.md` | Known risks with mitigations, and decisions still needed |

## One-paragraph summary

A couples app that protects time together. Partners pair their phones, social media is paused on a shared schedule (default 6 PM to 9 AM), and either partner can unlock time in three warm ways: scanning the other's rotating QR code in person, asking for approval by push or email, or spending minutes earned through shared challenges and spontaneous "kudos" from the partner. Minutes expire after 7 days so nobody can stockpile their way around the app. Everything is mutual and equal: it is not about control, it is about being intentional and really connecting. iPhone first, Android after the iPhone app is excellent, one subscription covers both partners.
