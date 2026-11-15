# C — Approved Design Baseline Register

**Version:** 0.1 · 15 Nov 2026 · **Status:** Audit and plan — **Pending Owner Approval**. Read-only audit: no code, test, setting, data, firmware or distribution setting was changed. "Today" = build 216 source (branch `ios/checkpoint-f-ride`, commit `4e2e9dc`), read, not run in this audit. Test results quoted are from recorded CI runs, named each time.
Source of truth: GitHub branch `docs/cyclift-governance`. Statuses use the owner's words where recorded.

| # | Subject | Governing document | Version · commit | Standing | Decision record |
|---|---|---|---|---|---|
| 1 | Global navigation | `product/profile/nav-v12/final/NAVIGATION_V12_FINAL_VISUAL_SPECIFICATION.md` | rev 1.1 · `6cc4076f` | **Current Approved — Visual Design Baseline; implementation not authorized** | `decisions/2026-11-15_navigation-v12…` |
| 2 | Train emblem | — | — | **Not approved.** Temporary mark proposed (H) | — |
| 3 | Training Hub | `product/train/v14/*` | v1.4 | **Current Approved — Design Baseline** | `decisions/2026-11-14_training-hub-v14…` |
| 4 | Cycling minimise | `TRAINING_HUB_V14_CYCLING_SAFETY_GATE.md` | v1.4 | Blocked pending safety gate | same |
| 5 | Progress hero and Evolution Track | `product/progress/PROGRESS_V23_COMPACT_HERO.md` | v0.1 · `0f38f06` | **Approved visual baseline** (design only) | `decisions/2026-11-13_progress…` |
| 6 | Progress sections | `PROGRESS_V23_VISUAL_REFINEMENT.md` | v0.1 | Direction approved (Variant A); document Current Draft | memory of owner review 13 Nov; no separate record |
| 7 | Athlete Evolution criteria | `PROGRESS_V2_RESEARCH_AND_FRAMEWORK.md` | v0.1 | **Not approved.** No thresholds exist | — |
| 8 | Onboarding Page 2 | `product/onboarding/v34/…ATHLETIC_ROSTER.md` | v0.1 · `b521cbf3` | **Selected Page 2 Design Baseline** — not implemented or tested | `decisions/2026-11-15_onboarding-v34…` |
| 9 | Onboarding pages 1, 3–7 | `product/onboarding/v33/*` | v0.1 · `f5ef7331` | Structure is the current direction; **visual approval not recorded**; Page 3 priority removed, Page 7 identity line (decision 8) | — |
| 10 | Onboarding contracts, migration, interruption | `v33/…INTEGRATION_CONTRACTS.md`; `v20/ATHLETE_MODEL_AND_MIGRATION.md` | v0.1 | Proposals | — |
| 11 | Profile | `product/profile/v20/PROFILE_V20_DESIGN.md` | v0.1 · `59d5bf93` | **Architecture approved; visual design Pending Review** | `decisions/2026-11-15_profile-v20…` |
| 12 | Plan | `product/plan/PLAN_V2_SPECIFICATION.md` (+ `visual-v05-B`) | v0.6 | Visual direction **B approved as foundation**; specification Current Draft; prototype not accepted | conflict register items 21–27 |
| 13 | Home | Production Home (build 216) | — | Shipped baseline. **No approved Home specification.** v2.2 Pending Review; v2.3 ready for sign-off, not approved | index rows 24–28 |
| 14 | Coach — shipped rules | `ios/ADAPTIVE_COACH.md`, `BEHAVIOUR_CONTRACT.md` | release branch | Describes shipped behaviour | — |
| 15 | Coach — approval rule | `product/coach/AUTOADAPT_CORRECTION_PROPOSAL.md` | v0.1 | Rule decided 12 Nov; correction proposal **Pending Review**; not implemented | register 26 / 69 |
| 16 | Coach — future direction | `planning/adaptive-lifestyle-coach` Decisions 1–12 | — | Approved as planning; not implemented | — |
| 17 | Brand Book | v0.2 | — | Approved design baseline; theme values provisional | — |
| 18 | Themes | six names agreed | — | Token values and migration **not approved** | — |

## Conflicts and missing approvals
1. Home has no approved design; the Navigation v1.2 avatar route changes Home's header regardless.
2. Plan sheets show the old five-item dock; Navigation v1.2 governs.
3. Profile v2.0 lists "priority" and activities; Page 2 is now their first entry point — one shared component is required.
4. Onboarding v3.3 Pages 3 and 7 drawings predate today's decisions; corrected drawings are in Document F sheet F1.
5. "Stage" wording: onboarding and Progress may show only "Establishing your baseline" until criteria are approved.
6. Earlier documents (v2.0–v3.3 onboarding, Training Hub v1.0–v1.3, Navigation v1.0–v1.1) are kept as history, not superseded by deletion.
