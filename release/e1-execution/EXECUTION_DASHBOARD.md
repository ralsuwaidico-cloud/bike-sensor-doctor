# Cyclift — execution dashboard

Status: **Live tracker** · started 15 Nov 2026 · updated at every checkpoint.
Authorization: E1 safety implementation on the isolated branch `ios/e1-safety` (owner directive, 15 Nov). **Not authorized:** TestFlight upload, protected-branch merge, firmware, activation of redesigned features or of capabilities whose safety rules are undecided.

Evidence words used here: **written** = code exists on the branch · **compiled** = built in CI · **unit-tested** / **simulator-tested** = executed in CI, run number given · nothing here is physical-device evidence.

## 1. E1 tasks

Branch `ios/e1-safety` at `9f19af51` (from `4e2e9dc1`, the commit audited in E0). Statuses use the owner's scale. "Linux" = fast logic tests, run 87 on `9f19af51`: 416 executed, 0 failed, 2 skipped (both need a real read-only folder and can only run on iOS). **No iOS result exists yet for `9f19af51`**; iOS run 226 covers only the first batch (`d59193cf`). Section 8 has every run.

| Task | What | Status on `9f19af51` |
|---|---|---|
| E1-A1 | Unreadable store never overwritten; copy kept; recovery screen | Implemented but unverified — Linux passed; iOS pending |
| E1-A2 | Record-by-record decoding; bad records set aside; banner | Implemented but unverified — Linux passed; iOS pending |
| E1-A3 | Newer store read-only; unknown fields kept; one previous copy per launch | Implemented but unverified — Linux passed; iOS pending |
| E1-A4 | Six build-216 fixtures (made in CI by the build-216 code) open, save and relaunch with no difference | Implemented but unverified — Linux: 0 differences in all six; iOS does not run this test (fixtures are generated on Linux) |
| E1-A5 | Backup policy: launch-time changes need a verified copy; older-schema file kept; ordinary saves do not wait | Implemented but unverified — six new tests passed on Linux; iOS pending · policy awaits owner confirmation |
| E1-A6 | One-time clean-up: one write, only untouched placeholders moved, nothing on a failed write, no later writes | Implemented but unverified — Linux passed; the failed-write case skips on Linux, needs iOS |
| E1-B1 | One write per save; true only when stored; rollback; retry not a duplicate | Implemented but unverified — failed-write test passed on iOS for `d59193cf` only (run 226); must run again on `9f19af51` |
| E1-B2 | "Not saved" on ride, strength workout and strength log; banner on every screen | Partially implemented — no UI test; "saving" and "uncertain" are not separate states (the write is synchronous) |
| E1-C | Full-body edit without equipment; planner matrix (3 levels × 4 equipment sets × 5 lengths) | Implemented but unverified — matrix test is iOS-only and has never run |
| E1-D1 | Layout CI: zero tests or zero screenshots fails | Implemented but unverified — needs the full iOS run |
| E1-D2 | Largest text: Plan day column fixed; Home ring value, Plan list titles, Profile rows still truncate | Partially implemented |
| E1-E | Every automatic increase held in both engines until the policy engine exists (owner decision 15 Nov) | Implemented but unverified — Linux passed; iOS pending |
| E1-F1 | Ride completes the planned ride of the day it started | Implemented but unverified — Linux passed; iOS pending |
| E1-F3 | Ride timing with an injectable clock | Implemented but unverified — iOS-only; never compiled |
| E1-F4 | Delete all data: safety copies, schema copy, temporary exports, device reports, diagnostic history | Partially implemented — copies tested on Linux; exports and diagnostics have no test |
| E1-F5 | Health-hold gate on every ride-start route | Implemented but unverified — iOS-only; never compiled. Location permission not enforced (open decision) |
| E1-G | Release accounting | Blocked on nothing; not started — needed before an upload request |

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
| 1 | Confirm the backup failure policy (`decisions/2026-11-15_e1-backup-failure-policy.md`) | E1 acceptance |
| 2 | Enforce location permission at ride start? Today a phone ride starts without it and the UI tests rely on that | E1-F5 completeness |
| 3 | Visuals of onboarding pages 1, 3–7; Profile visuals; temporary Train mark; Home quick menu; primary sports | UX1 |
| 4 | Thresholds of a "small" step; protective allowlist; old 7/6 ratings; fueling rules | UX3 Coach |

Resolved 15 Nov: all automatic increases held (owner); synthetic build-216 fixtures accepted as strong evidence (owner); set-order differences are not data loss (owner).

## 6. Earliest safe integrated TestFlight checkpoint

**E1**, after its acceptance gate and a separate release request. Not before the full iOS run on the release commit is green and E1-G is done.

## 7. Conflicts between the directive and the repository documentation

| Conflict | Records | Resolution taken | Needs a decision? |
|---|---|---|---|
| Scope of the interim hold | Decision record of 15 Nov; directive E1-E | Owner decided 15 Nov: all automatic increases held in both engines | No — resolved |
| Layout defects | Readiness package: triage at a checkpoint; directive E1-D: fix in E1 | Directive followed; added as E1-D2 | No |
| Diagnostics "pass unmodified" | E0 report; run 225 | One assertion restated with the reason in the file (timestamp rounding, no data lost); all others unchanged | No — disclosed |
| Themes and Arabic | Readiness package: six themes in UX1; directive §8: additional themes and Arabic as later capability releases | Directive followed; architecture keeps both | No |

## 8. CI evidence, by commit

A result counts only for the commit in its row.

| Run | Commit | Result |
|---|---|---|
| Fast logic 75–78 | `d59193cf` … `d3a6aca0` | Failed on my test tooling, not on product code |
| Fast logic 79 | `62bb022d` | 404 executed, 1 skipped, 1 failed (my time-fit change; reverted) |
| Fast logic 80 | `ed761478` | Cancelled by my own later push |
| Fast logic 81 | `75859cff` | 405 executed, 1 skipped, 1 failed (wrong premise in my healthy-store test; corrected with the reason) |
| Fast logic 83, 84 | `58f637dd`, `03bc29a8` | 406 executed, 1 skipped, 1 failed test (member order of one stored set; not data loss) |
| Fast logic 86 | `410eeda5` | Passed; total not recorded (reporting fault of mine, fixed in the next commit) |
| Fast logic 87 | `9f19af51` | **416 executed, 0 failed, 2 skipped** (read-only-folder tests; iOS only). Six build-216 fixtures: 0 differences each |
| iOS 226 (quick) | `d59193cf` | Cancelled on owner authorization during screen tests. Before that: Debug and Release compiled; 688 unit tests executed, 2 tests failed (both since corrected); failed-write test passed; all 16 E0 diagnostics passed. Logs readable on `ci-logs` under `ios/run-226/` |
| iOS 227–232 | — | Cancelled while queued or replaced; no results |
| iOS 233 | `58f637dd` | Cancelled on owner authorization while queued; no results |
| iOS full run | `9f19af51` | Started 15 Nov; results pending. No quick run and no override on this commit, so the release job refuses to archive; no upload requested |
