# Cyclift — Approved Screens Register

Last updated: 20 Nov 2026, 18:30 (Dubai) · Screens recorded: 2

This is the cumulative record of every UI/UX decision the owner has approved. The latest explicitly approved decision for a screen is the source of truth. Older designs, provisional sketches, newer unapproved implementations and screenshots that merely passed a check never replace it. An earlier decision is never altered: a revision is added to the screen's history and the earlier one is kept as superseded.

The five statuses below are separate facts and are never treated as interchangeable: **Approved design · Implemented in code · Compiled · Simulator-verified · Physically verified on iPhone.**

The visual book is `CYCLIFT_APPROVED_SCREENS.pdf` in this folder; images are in `assets/`.

## Summary

| # | ID | Screen | Approved design | Implemented in code | Compiled | Simulator-verified | Physically verified on iPhone |
|---|---|---|---|---|---|---|---|
| 1 | ONB-01 | Welcome | YES | YES | YES | YES — with limits | NO |
| 2 | ONB-02 | About You | YES | NOT YET | NOT YET | NOT YET | NO |

---

## Screen 1 — Welcome (ONB-01)

- **Navigation location:** Onboarding · first screen, shown before page 1 (About you). Shown once to a new athlete.
- **Approval date:** 20 Nov 2026, 16:59 (visual design and final wording); locked 17:01
- **Approval status:** APPROVED AND LOCKED — do not modify without the owner's approval
- **Original design reference and source:** No earlier design sheet existed for a welcome screen. The canonical design is the owner's written "Screen 1 final decision" (20 Nov 2026) as shown in the simulator screenshot he approved, with the final wording he then set.
- **Implementation commit:** Screen and interaction 08b4bfbf · hero image 7da39754 · final wording 58cec7b5 (branch ios/lab). Not in any TestFlight build.

### Exact approved wording

- **Headline:** Your evolution starts here.
- **Supporting text:** Your goals. Your training. A better you, every day.
- **Circular control:** Hold to begin
- **Helper:** Hold for 3 seconds

### Approved layout, visual elements and interactions

- Black-hole / orbital hero in the upper-middle of the screen: a still image made by the drawing routine of the approved Progress design sheets (baseline form, one image per theme). Static.
- Order, top to bottom: hero · headline · supporting text · circular hold control. Centred, generous spacing.
- Press and hold the circular control for three seconds; a progress ring fills around it; the control responds subtly to touch; releasing early resets the ring; a tap does nothing.
- Subtle haptics: light when the hold begins, success when it completes.
- On completion the welcome screen dissolves (fade with a slight scale and blur), then About you appears.
- Accessible alternative: VoiceOver / Switch Control activation starts onboarding without the sustained hold.
- No Cyclift icon, no app-name heading, no technical legend, no explanatory paragraph.

### Mandatory functionality and dependencies

- Completing the hold must do what the earlier "Get started" button did: the athlete continues without an account (guest state set) and onboarding page 1 opens. Dependency: the onboarding entry in OnboardingV34.swift.
- Lab controls (badge, Theme, Scenario, Restore) are not part of this screen and must not appear in the main app.

### Explicitly rejected alternatives

- The earlier welcome: Cyclift icon and name, the "Seven short pages…" paragraph, the three-mark legend (Declared by you / Coach's proposal / Measured evidence), the "About two minutes…" line, and a tap "Get started" button.
- The flat Progress placeholder as the finished hero (allowed only as a fallback if an image is missing).
- Flashy, cinematic or game-like transitions; continuous animation is optional and not required.

### Status

| Stage | State | Evidence |
|---|---|---|
| Approved design | YES | Owner, 20 Nov 2026 16:59; locked 17:01. |
| Implemented in code | YES | Commits above. |
| Compiled | YES | Fast check 24 (run 44740474661) built the Lab app at commit c67e1883. |
| Simulator-verified | YES — with limits | iPhone 15 Pro simulator, Obsidian. Fast check 24: the four approved strings exact; tap and a 1-second hold do nothing; ring reported empty after early release; a finger drifting about 10 pt still completes; About you opens; seven pages run to an approved plan. Main app (iOS run 307, commit 3b326a3d, earlier wording, a different simulator size): no Lab strip, holding starts onboarding. |
| Physically verified on iPhone | NO | Nothing on this screen has been checked on a real iPhone. |

- **Visual verification:** Owner approved the simulator screenshot (fast check 23) and set the final wording; the final-wording screenshot (fast check 24) is the image in this book. Obsidian only.
- **Functional verification:** Simulator only, as listed under Simulator-verified.

### Remaining work or limitations

- Real iPhone: VoiceOver / Switch Control activation, the haptics, and how the dissolve looks and feels.
- Other five themes and the largest text size have no screenshot with the hero image.
- Main-app evidence predates the final wording (the wording change itself was verified in Lab).
- Observation from fast check 25, cause not proven: a hold begun the instant the app launched did not open page 1; with a two-second wait it did. To be checked on a real iPhone.
- Open choices left to the owner: richer hero form; subtle hero motion.

### Images

- `assets/S01_welcome_approved_sim_c67e1883.png` — APPROVED DESIGN — as implemented. iPhone 15 Pro simulator, Obsidian, commit c67e1883 (fast check 24). The yellow badge and Theme / Scenario / Restore controls are Cyclift Lab controls, not part of the screen.

### Decision history

| When | Decision | State |
|---|---|---|
| 20 Nov 2026, 15:12 | Direction approved: black-hole hero, three-second hold, dissolve. Wording then: "Start your journey to a better lifestyle" / "See where you fit in the athletic world, and build a routine around your life." / "Hold to start". | SUPERSEDED (wording only) |
| 20 Nov 2026, 15:28 | Hero must be the original black-hole artwork, not the flat placeholder; static image acceptable. | IN FORCE |
| 20 Nov 2026, 16:59 | Visual design approved with the final wording recorded above. | IN FORCE |
| 20 Nov 2026, 17:01 | Approved and locked as the canonical Screen 1. | IN FORCE |

---

## Screen 2 — About You (ONB-02)

- **Navigation location:** Onboarding · page 1 of 7, directly after Welcome. The same measurements are editable later in Profile › Personal details.
- **Approval date:** 20 Nov 2026, 17:09 (design); revised and approved 18:24 (all four fields mandatory, compact units selector, simplified page)
- **Approval status:** APPROVED DESIGN AND REQUIREMENTS — IMPLEMENTATION VERIFICATION PENDING
- **Original design reference and source:** Onboarding v3.3 design sheet Y1, page 1 (15 Nov 2026) — previously an unapproved direction; approved by the owner on 20 Nov 2026 as the layout for this screen, with the modifications listed below. No drawing of the modified screen exists; the sheet image is kept as the reference until an accurate implementation screenshot has been verified.
- **Implementation commit:** Earlier version (optional fields, full-width units): 848f015f, check b63361d8 (branch ios/lab). The 18:24 revision is NOT yet implemented. Not in any TestFlight build.

### Exact approved wording

- **Page title:** About you
- **Fields:** First name · Date of birth · Weight · Height
- **Units selector:** Units: Metric ▾ (choices: Metric, Imperial)
- **Button:** Continue
- **Removed:** Every "optional" label; the line "Only your name is needed. Nothing is estimated from blanks — a missing weight stays unknown."; redundant technical descriptions.

### Approved layout, visual elements and interactions

- Keep the clean, minimal v3.3 layout: large editable first name, simple Date of birth, Weight and Height rows, minimal typography and separators, clear Continue button, existing step navigation.
- MODIFICATION — a fourth row, Height (not on the v3.3 sheet).
- MODIFICATION — units: the full-width Metric / Imperial control is replaced by a compact, discreet native-style selector near the Weight and Height rows, presented as "Units: Metric ▾"; tapping it offers Metric or Imperial. Changing units converts the displayed values without changing the underlying measurements.
- MODIFICATION — date of birth: the compact date-entry sheet with direct day, month and year entry, Cancel and Done; no full-screen scrolling wheel.
- MODIFICATION — the bottom explanatory paragraph and all "optional" labels are removed.
- When information is missing or invalid, the page gives a clear indication of what must be corrected.

### Mandatory functionality and dependencies

- All four fields are mandatory for a new athlete: first name, date of birth, weight, height. Continue is disabled until all four hold valid values.
- First name not blank. Date of birth valid and not in the future. Weight and height positive and within validated ranges. Nothing is filled in automatically and no assumed values are used.
- The four values are kept in the authoritative athlete model and persist after reopening; Back and Continue preserve what was entered; Metric / Imperial conversion is accurate.
- BMI = weight in kilograms ÷ (height in metres)², only from actual valid measurements; descriptive only — not body-fat, never a basis for automatic training-load decisions.
- Existing athletes upgrading from an older version: no record is erased and no unsafe migration is forced because height was missing. Existing data is handled separately from the new-athlete requirement.
- Measurements stay editable later through Profile.

### Explicitly rejected alternatives

- Build 6's large boxed input cards.
- The full-screen scrolling date-of-birth wheel.
- The full-width Metric / Imperial segmented control (unnecessarily large).
- Optional date of birth, weight or height for a new athlete (superseded 18:24).
- Estimating or silently filling missing measurements.

### Status

| Stage | State | Evidence |
|---|---|---|
| Approved design | YES | Owner, 20 Nov 2026 17:09; requirements revised and approved 18:24. |
| Implemented in code | NOT YET | Only the earlier version exists (848f015f). The 18:24 revision — four mandatory fields, compact units selector, removed labels and paragraph, missing-information indication — is not written yet. |
| Compiled | NOT YET | Nothing of the 18:24 revision has been compiled. |
| Simulator-verified | NOT YET | Fast check 26 (run 44747245997, commit b63361d8) passed on the EARLIER version only: date typed as day/month/year with no wheel, 31 April rejected, Cancel stores nothing, 70 kg / 175 cm entered, Imperial showed 154 lb and 5 ft 9 in with the stored values unchanged, Back and Continue kept the answers, all four present after reopening. It does not verify the approved requirements. |
| Physically verified on iPhone | NO | Nothing on this screen has been checked on a real iPhone. |

- **Visual verification:** PENDING. Not verified until the corrected screenshot has been reviewed by the owner.
- **Functional verification:** PENDING for the approved requirements. Earlier version: fast check 26 on the simulator and 15 logic tests (BMI arithmetic, no BMI without two valid measurements, height in both unit systems, leap years, future dates, older records without a height).

### Remaining work or limitations

- Implement the 18:24 revision, then: updated About you screenshot, date-of-birth sheet screenshot, focused functional check.
- Genuine defects found by fast checks 25–26: none confirmed in the app. One open observation: a hold on Welcome begun the instant the app launched did not open this page (cause not proven; see Screen 1).
- Two of the three on-screen "rejected date" cases in fast check 26 were garbled by the check itself; to be corrected.
- Date sheet, seen by the owner and not yet ruled on: an empty gap above the keypad and a second "Done" pill above the keyboard.
- Where BMI should be shown — it is calculated but appears nowhere; owner decision needed.
- Limits chosen by the implementation, to be confirmed by the owner: height 120–230 cm; age 13–100 (the earlier wheel's limit). Weight keeps its existing 30–200 kg rule.
- Profile › Personal details still uses the date wheel (left for the Profile review).
- Redesigned main app, other themes, largest text size, real iPhone: not checked.

### Images

- `assets/S02_about_you_reference_v33_Y1_page1.png` — APPROVED DESIGN REFERENCE — onboarding v3.3 sheet Y1, page 1 (actual sheet image). Approved WITH MODIFICATIONS not drawn on it: a Height row; "Units: Metric ▾" compact selector in place of the full-width control; no "optional" labels; no paragraph above Continue; date of birth entered in a compact day / month / year sheet.

### Decision history

| When | Decision | State |
|---|---|---|
| 20 Nov 2026, 17:09 | Approved: the v3.3 reference layout with height, the compact date-of-birth entry, unit handling and the BMI rule. First name mandatory; date of birth, weight and height optional initially. | SUPERSEDED IN PART (optional fields) |
| 20 Nov 2026, 18:24 | Revised and approved: all four fields mandatory with Continue disabled until valid and a clear indication of what to correct; compact "Units: Metric ▾" selector; "optional" labels and the bottom paragraph removed; date sheet preserved; existing athletes not forced through a migration. | IN FORCE |
