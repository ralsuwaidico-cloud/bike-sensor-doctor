# Cyclift — execution dashboard

Status: **Live tracker** · started 15 Nov 2026 · updated at every checkpoint.
Authorization: E1 safety implementation on the isolated branch `ios/e1-safety` (owner directive, 15 Nov). **Not authorized:** TestFlight upload, protected-branch merge, firmware, activation of redesigned features or of capabilities whose safety rules are undecided.

Evidence words used here: **written** = code exists on the branch · **compiled** = built in CI · **unit-tested** / **simulator-tested** = executed in CI, run number given · nothing here is physical-device evidence.

## 1. E1 tasks

Branch `ios/e1-safety`, created from `4e2e9dc1` (the commit audited in E0). First commit `d59193cf`.

| Task | What | Depends on | Tests that must pass | State |
|---|---|---|---|---|
| E1-A1 | Unreadable store never overwritten; copy kept; recovery screen | — | E0: UnreadableStoreIsNotOverwrittenAtLaunch, StageAtWhich…; E1DataIntegrity: unreadable ×4 | Written · not yet compiled |
| E1-A2 | Record-by-record decoding; raw bad records set aside | A1 | E0: MalformedRecordMatrix, OneBadStrengthRecord…; E1: eleven lists | Written · not yet compiled |
| E1-A3 | Newer store read-only; unknown fields kept; one previous good copy | A1 | E0: NewerStoreKeepsItsUnknownFields…; E1: newer, unknown, previous copy | Written · not yet compiled |
| E1-A4 | Build-216 fixtures open with zero loss (built by the build-216 serializer in CI) | A2 | New fixture job | **Not started** |
| E1-B1 | Save result at the store: one write, true only when stored, rollback on failure | A1 | E0: FailedWriteIsReportedAtTheSave; E1: one write, rollback, retry | Written · not yet compiled |
| E1-B2 | Save screens: "Not saved — Try again" for ride, strength workout, strength log | B1 | Flow tests unchanged; new UI test for the failed state | Written (alerts) · UI test **not started** · the five named states (recording / saving / saved / failed / uncertain) are **not** all modelled yet |
| E1-C | Full-body edit without equipment: difficulty of bodyweight hip exercises; time-fit keeps required patterns | — | E0 PlanEdit diagnostic; PlanEditPreviewApplyTests flow; matrix level × equipment × minutes | Fix written · matrix test **not started** |
| E1-D1 | Layout CI: settings reach the tests; zero tests or zero screenshots = failure | — | Deliberate dry run | Written |
| E1-D2 | Largest-text truncation and stacked weekday letters on production screens; truncation detection | D1 | Layout audit | **Not started** |
| E1-E | Increases in sets, intervals, ride minutes held for approval; increases already in force kept | — | New tests; existing adaptive tests reviewed one by one | Written · tests **not started** |
| E1-F1 | Planned-ride completion after midnight / late import | B1 | New tests | **Not started** |
| E1-F2 | One write per save (was six) | B1 | E1: OneSaveIsOneWrite | Written |
| E1-F3 | Ride timing test: injectable clock | — | New deterministic test; existing test unchanged | **Not started** |
| E1-F4 | Delete all data: temporary exports, device diagnostic reports, sensor history; ×20 in CI | — | New test; journey ×20 | Safety copies done · the rest **not started** |
| E1-F5 | Ride-start gate on all five routes (pause, health stop, location) | — | Per-route tests | **Not started** |
| E1-G | Release accounting (no upload with an unnamed failing test) | D1 | Dry run, no upload | **Not started** |

## 2. Parallel workstreams that do not touch E1 files

| Workstream | Branch (to create) | Owns | Can start |
|---|---|---|---|
| A · Foundation and navigation | `ios/ux-foundation` | Named destinations, dock (Navigation v1.2 rev 1.1), design tokens, string catalogue | Design-system and dock as new files now; the edit of `ContentView` waits for E1 (it now hosts the recovery screen) |
| B · Onboarding and Profile | `ios/ux-athlete` | New onboarding pages, Profile v2.0, shared editors, roster model | New views now; stored fields wait for the E1 schema guard |
| C · Training Hub | `ios/ux-train` | Panel, recorder presentation, review | New views now; save states wait for E1-B |
| D · Plan, Home, Progress | `ios/ux-plan` | Plan views, Progress hero, approved Home changes | After A |
| Coach foundation | `ios/c0-coach` | Policy table, decision ledger, typed proposals (new files) | Now, in shadow mode |

None of these is started. E1 is the only code work under way.

## 3. Shared contracts to agree before integration

1. **Save result** — `Store.durably`, `saveFailure`, `storage` (in E1). Every recorder and the Coach read these; nothing else may report "saved".
2. **Storage file** — schema 4, additive fields only; unknown fields carried; newer schema read-only.
3. **Named destinations** — one enum replacing tab numbers 0–4; ride start goes through one gate.
4. **Athlete record** — one roster, one set of profile fields, edited by the same editor from onboarding and Profile.
5. **Coach proposal** — typed change, evidence, origin (fact / rule / AI), policy version, outcome, reversal.
6. **Review** — three optional ratings; "not answered" is a stored value.

## 4. Approval status of every main screen

| Screen | Baseline | Status |
|---|---|---|
| Navigation | v1.2 rev 1.1 | **Approved** visual baseline · Train emblem pending (placeholder needs approval) |
| Onboarding | v3.3 structure; Page 2 = v3.4 Athletic Roster; Page 3 and 7 changes; Coach wording of 15 Nov | Page 2 **selected**; visuals of pages 1, 3–7 **not approved** |
| Profile | v2.0 six sections, via Home avatar | Architecture **approved**; visuals pending |
| Home | Build-216 Home + decisions of 12 Nov | Redesign **not approved**; quick-menu retirement undecided |
| Plan | Schedule-first: Weekly Calendar + Recurring Plan | Direction **approved**; integration design pending |
| Train | Training Hub v1.4 | **Approved** design baseline · cycling minimise blocked |
| Progress | Compact hero | Hero **approved** · stage criteria unresolved (no stage shown) |
| Coach | Design review v2 + progression rule of 15 Nov | Direction **approved** · screens, thresholds, allowlist pending |

## 5. Decisions that genuinely block development

| # | Decision | Blocks |
|---|---|---|
| 1 | Should small **load and repetition** steps also be held until the policy engine exists? Today they still apply automatically through two paths (adaptive coach and planner rebuild). The directive's E1-E list names sets, intervals and ride duration, so only those are held. | Completeness of E1-E |
| 2 | Build-216 fixture: synthetic in CI (planned). Is your own export also wanted, kept private, for final confidence? | E1 acceptance confidence, not the work |
| 3 | Visuals of onboarding pages 1, 3–7; Profile visuals; temporary Train mark; Home quick menu; primary sports | UX1 |
| 4 | Thresholds of a "small" step; protective allowlist; old 7/6 ratings; fueling rules | UX3 Coach |

## 6. Earliest safe integrated TestFlight checkpoint

**E1**, after its acceptance gate and a separate release request. Not before: the five release blockers are open until the tests above have run green in CI and the build-216 fixtures open without loss.

## 7. Conflicts between the directive and the repository documentation

| Conflict | Records | Resolution taken | Needs a decision? |
|---|---|---|---|
| Scope of the interim hold | Decision record of 15 Nov and readiness package: "all increases are proposals"; directive E1-E: sets, intervals, ride duration and other non-approved categories | Followed the directive's list; load and repetition steps unchanged | **Yes** — item 1 above |
| Same change decided by two engines | Coach finding N-03; directive §4 | Not resolved by the hold as scoped; both engines still decide load and repetition steps | Follows item 1 |
| Layout defects | Readiness package: triage at a checkpoint; directive E1-D: fix in E1 | Directive followed; added as E1-D2 | No |
| Diagnostics "pass unmodified" | E0 report; run 225 | One assertion restated with the reason in the file (timestamp rounding, no data lost); all others unchanged | No — disclosed |
| Themes and Arabic | Readiness package: six themes in UX1; directive §8: additional themes and Arabic as later capability releases | Directive followed; architecture keeps both | No |
