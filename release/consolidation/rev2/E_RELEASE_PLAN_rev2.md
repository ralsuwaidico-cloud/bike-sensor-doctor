# E — Revised TestFlight Strategy (revision 2)

**Revision 2 · 15 Nov 2026 · Status:** Corrected consolidation — **Pending Owner Final Review. No implementation authorized.** Read-only: no code, data, branch or distribution change. Drawings are static; none is simulator or device evidence. Revision 1 documents are kept unchanged in the parent folder. The TestFlight status in revision 1 stands: last upload build 216 on 10 Nov 2026, 10:26 UTC; nothing since; tester membership not verifiable from here.

## Two kinds of build
**Engineering validation builds (E)** — small, internal, same look as build 216. Purpose: fixes, migration, persistence, regression. **Integrated UX builds (U)** — review releases in which every tab uses the same navigation and a coherent design.

| Build | Contents | Gate |
|---|---|---|
| **E1** | Causes of the two failing tests fixed; save-result model and visible write failure; Coach increases become proposals; protective changes listed with Undo; build-216 fixture and migration tests | Full matrix green twice; no increase without approval; old store identical |
| **E2** | Additive fields (main-sport flag, save state); onboarding stage mapping; strength restore after relaunch; background-recording check on a device | Migration and persistence tests; device checklist |
| **U1** | New dock on **every** tab; Profile from the Home avatar (six sections); seven-page onboarding with the roster | Approvals 1–4 in H; all journeys pass |
| **U2** | Training Hub: panel, activity selector, strength recorder, minimise for strength, finish, save states, review | Strength journey; no duplicate session |
| **U3** | Plan (Weekly Calendar, Recurring Plan, proposals, Move); Progress (hero, unevaluated track, sections); Home changes if signed off | Approvals 5–7; lab defects closed |
Safety work (E1, E2) comes first and is not shortened to bring U1 forward.

## What each tab shows in each build
| Build | Navigation | Home | Plan | Progress | Train | Profile | Onboarding |
|---|---|---|---|---|---|---|---|
| 216 (today) | Five pages + centre button | Production | Production | Production | Current hub; Ride screen | Tab | Five stages |
| E1 | unchanged | unchanged | unchanged; edit works | unchanged | unchanged; save failure visible | unchanged | unchanged |
| E2 | unchanged | unchanged | unchanged | unchanged | unchanged | unchanged | unchanged (resume mapping inside) |
| **U1** | **v1.2 dock** | Production content, avatar top right | Production content | Production content | Current hub from the ball; Ride screen | **v2.0 via avatar** | **v3.3 + v3.4** |
| U2 | v1.2 | as U1 | as U1 | as U1 | **v1.4 (strength); Ride screen kept** | v2.0 | v3.3 + v3.4 |
| U3 | v1.2 | v2.3 if signed off, else production | **v2.0** | **compact hero, no stage** | v1.4 | v2.0 | v3.3 + v3.4 |
One navigation generation from U1 onward. In U1 and U2 the content of Home, Plan and Progress is still the production design; that is stated in the release notes.
Deferred beyond U3: cycling minimise and Focus/Map layouts; recovery recording; supersets; Intensity; sport type per session; stage evaluation; Coach timeline; goal programs; theme migration.
