# A — Executive Readiness Report

**Version:** 0.1 · 15 Nov 2026 · **Status:** Audit and plan — **Pending Owner Approval**. Read-only audit: no code, test, setting, data, firmware or distribution setting was changed. "Today" = build 216 source (branch `ios/checkpoint-f-ride`, commit `4e2e9dc`), read, not run in this audit. Test results quoted are from recorded CI runs, named each time.

## 1. Where Cyclift is today
- **A working app exists.** Build 216 (version 1.0.0) records rides and strength sessions, generates a rules-based plan, adapts it after check-ins, and stores everything on the iPhone. The recorded hybrid, cycling and strength journeys passed in the latest CI run (run 221, 11 Nov).
- **The latest code does not pass its tests.** Two tests fail in run 221: the Plan edit-and-apply journey and one ride-recording unit test. Because tests failed, no build after 216 could be uploaded.
- **The design work is ahead of the app.** Of 74 tracked features: 10 are implemented and verified, 14 implemented but not verified, 22 partly implemented, 12 approved designs not built, 3 prototype only, 9 proposed and not approved, 3 blocked, 1 switched off.
- **The Coach is rules-based.** There is no conversational or generative coach in the code.

## 2. What is approved, and what is not
| Area | Standing |
|---|---|
| Navigation v1.2 rev 1.1 | Approved visual baseline. Emblem not approved |
| Training Hub v1.4 | Approved design baseline. Cycling minimise blocked; recovery recording, Intensity, save-result handling pending |
| Progress compact hero | Approved visual baseline. Stage rules **not approved**; proof of concept has open failures |
| Onboarding Page 2 (v3.4 roster) | Selected design baseline (today's decision) |
| Onboarding pages 1, 3–7 (v3.3) | Current direction; **no recorded visual approval** |
| Profile v2.0 | Architecture approved; **visual design pending** |
| Plan v2.0 | Visual direction B approved as foundation; specification still a draft; prototype not accepted |
| Home | **No approved design.** v2.3 is "ready for sign-off", not approved. Production Home stays |
| Coach approval rule | Decided (12 Nov): increases need approval. **Not implemented** |

## 3. Biggest gaps
1. **Coach changes plans without approval.** Small progressions are applied automatically by default — against your decision.
2. **Two failing tests** on the release branch (causes not yet confirmed; hypotheses in Document G).
3. **A ride in progress is held only in memory.** If the app is terminated mid-ride, the ride is lost. This is why cycling minimise stays blocked.
4. **Save results are not visible.** A failed write is kept in an internal variable; the athlete is not told.
5. **Missing approvals** that gate milestones: Profile visuals, onboarding pages 1 and 3–7, Home, Plan specification, stage rules.
6. **New stored fields** are needed (main-sport flag; later, sport type per session) with a tested migration.
7. **Indoor cycling, mountain bike and bodyweight are labels, not capabilities** (Document D §3).

## 4. What I propose
Five small releases instead of one large one, each installable and reversible (Document E):
**TestFlight 1** integrity and Coach approval (looks the same) → **2** onboarding and Profile → **3** navigation and strength Training Hub (first build that feels like the new Cyclift) → **4** Plan and Coach → **5** Home and Progress.
Deferred: cycling minimise, recovery recording, Intensity rating, stage evaluation, six-theme migration, cloud, LILYGO.

## 5. TestFlight in one paragraph
The last upload was **build 216 on 10 Nov 2026, 10:26 UTC**; Apple finished processing it and the pipeline reported it installable by internal testers at 10:29 UTC. Nothing has been uploaded since: the five later runs all failed tests, none requested an upload, and no app code has been committed since 11 Nov (the work since has been design). I cannot see App Store Connect from this session, so tester-group membership and current build expiry are **not verified**.

## 6. The package
A this report · B feature tracker (spreadsheet, with traceability) · C baseline register · D architecture, data and journeys · E release plan and TestFlight status · F visual review (four sheets) · G risks, defects, blockers · H approval checklist.
