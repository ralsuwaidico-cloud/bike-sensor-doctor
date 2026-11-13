# Training Hub v1.1 — A · Product specification

Status: **Current Draft — design exploration, pending owner review** · Version 0.1 · 13 Nov 2026 · Level 3
Authorised: audit, architecture, specifications and static mock-ups only. **Production implementation not approved. Onboarding out of scope.**
Nothing was built or run. Code read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. All figures in the sheets are illustrative.
Supersedes the layout proposals of `product/train/TRAINING_HUB_V1_DESIGN.md` v0.1 (left unchanged as the earlier round). Its audit (§2) still applies.

**Not received:** the WHOOP activity-selection screenshots referred to in the brief did not arrive (text only). The
selector follows the principles the brief lists, not the images.

## 1. Sheets (`sheets/`)

S01 Train symbol · S02 Compact panel · S03 Expanded hub · S04 Activity selector and icon family · S05 Cycling ·
S06 Running (future illustration) · S07 Other endurance templates · S08 Strength preparation · S09 Strength logging
inputs · S10 Strength execution and rest · S11 Recovery and rest day · S12 Post-session review · S13 Finish and save ·
S14 Journey · S15 Themes and accessibility.

## 2. Principle

One Training Hub. Many activities. The right recording experience for each. One consistent way to finish and review.

## 3. Screen hierarchy

| Level | Screen | Purpose | Primary action |
|---|---|---|---|
| 0 | Train button | Global entry; shows a session in progress | Open |
| 1 | Compact panel | Today's primary session | Start / Resume |
| 2 | Expanded hub | Your activities · planned today · recent · saved routines · explore all | Start the primary session |
| 2a | Activity selector | Search and filter the catalogue | Choose an activity |
| 3 | Preparation | What, with what, recorded by what | Start |
| 4 | Recording (full screen) | Endurance cockpit · Strength logging · Recovery timer | Pause (endurance) · Log set (strength) |
| 5 | Finish | What was actually recorded | Save |
| 6 | Saved + optional review | Feedback | Done |

## 4. Behaviours

- **Compact panel:** one primary session and one Start or Resume. With two sessions the second is one quiet row. With
  none, or on a rest day, a sentence and up to three small activity shortcuts plus "All". A session opened from Plan
  shows that session and says it is the same record.
- **Expansion:** swipe up, or the cue as an accessible control. Hub sections appear only when they have content; a
  single-discipline athlete sees only their activities.
- **Selector:** search by name and common alternatives ("weights", "gym", "lifting" → Resistance training); filters
  All · Training · Recovery · Wellness · Sleep (labels to be reviewed — Recovery and Wellness overlap); each row says
  how it is captured: **Record**, **Timer**, or **Log only**; an activity that cannot be recorded says so everywhere.
- **Recording:** full screen, one family layout per kind of activity (documents C, D, E).
- **Finish and review:** the record is saved first; the review is optional and attaches to the saved record (document F).

## 5. Special states

No plan · rest day · two sessions · missed session (stated in words; moving it happens in Plan) · session active or
paused (panel shows only Resume) · completed today · selected sport not recordable · sensor missing before start ·
sensor lost during recording · GPS not acquired (shown as "—", distinct from a measured zero) · app interrupted ·
save failed · nothing recorded · partial session · health hold (unchanged from today).

## 6. How saved preferences are consumed (no onboarding work)

The hub reads three things that onboarding or Profile will provide: athlete profile (Endurance / Strength / Hybrid),
the list of selected activities, and which is primary. Today the code has the first as `TrainingMode` and an unused
`sports` list (see `PROGRESS_V21_ARCHITECTURE_AND_AUDIT.md` §3). "Your activities" = selected ∩ selectable in the
registry; anything selected but not recordable appears as Log only. Until the selection is collected, the default is
derived from `TrainingMode`.

## 7. Comparison with today

| | Today (from code) | Proposed | Basis |
|---|---|---|---|
| Taps to start a planned workout | Centre → Start → Start workout (3) | Train → Start → Start workout (3) | Traced; **no reduction** unless Start skips preparation (owner decision) |
| Taps to log a strength set as prescribed | 1 (Log on the next-set card) | 1 | Traced |
| Change load by one step | 1 tap (±, fixed 2.5 kg / 5 lb) | 1 tap; typed entry adds a second route | Traced / design |
| Superset navigation | Group letter shown; sequencing not verified in code | Explicit A1 → A2 → rest → next round | Design hypothesis |
| Rest countdown | Present on the next-set card | Fixed strip with adjust and skip | Design hypothesis |
| Start a free activity | Centre → hub → Other session → pick (3+) | Train → activity tile (2) | Design hypothesis; today's path traced |
| Ways to reach Finish (strength) | 3 | 1 | Traced |
| Controls under each exercise (preparation) | 2 | 0 | Traced |
| Presentation owners | 5 plus the hub overlay | 1 | Traced / proposal |
| Recover from interruption (strength) | Yes — stored active session | Kept | Traced |
| Recover from interruption (ride) | Not verified | To be audited | — |
| Activities offered | Cycling, strength | Registry of many, most Log only or future | Proposal |

No timings or usability measurements exist; anything not marked "Traced" is a hypothesis.
