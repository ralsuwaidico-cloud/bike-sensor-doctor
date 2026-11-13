# Documentation index — which file governs each subject

Status: Current Draft · Version 0.4 · 12 Nov 2026

Statuses: **Current Approved** · **Current Draft** · **Historical** · **Superseded** · **Pending Review**.
Statuses below are recorded **here only** — no existing file was edited to add them. Only the owner assigns
"Current Approved" and "Superseded"; where a label below is my reading, it says "(proposed label)".

Location key: **gov** = this branch (`docs/cyclift-governance`) · **rel** = iPhone release branch
(`ios/checkpoint-f-ride`) · **hw** = `docs/hardware-handover` · **lab** = `proto/ui-lab` · **project** = Claude
project (reference copies and documents not yet in GitHub).

## One authoritative file per subject

| Subject | Authoritative file | Location | Status |
|---|---|---|---|
| Governance, mission, priorities | Master Project Instructions v2.0 | Project settings | Current Approved |
| Brand, product principles, design system | `brand/CYCLIFT_BRAND_BOOK.md` (v0.2) | gov | **Current Approved — design baseline** (12 Nov); §15 items provisional; no theme values or migration approved |
| Discipline-colour migration impact | `brand/DISCIPLINE_COLOUR_MIGRATION_IMPACT.md` | gov | Current Draft (assessment only) |
| Documentation branch form | `governance/DOCUMENTATION_BRANCH_ARCHITECTURE.md` | gov | Current Draft (recommendation) |
| Proposed Instruction edits | `governance/PROPOSED_PROJECT_INSTRUCTION_CHANGES.md` v0.3 | gov | Approved in principle (12 Nov); waiting for the owner to apply |
| Contradictions and rulings | `governance/CONFLICT_REGISTER.md` | gov | Current Draft |
| Owner decisions | `decisions/2026-11-10_home-v2-and-themes.md`, `decisions/2026-11-11_adaptive-lifestyle-coach-decisions-1-12.md` | project | Current Approved |
| **Home** — shipped behaviour | Production Home in build 216; map `ios/HOME_V2_IMPLEMENTATION_MAP.md` | rel | Current Approved (shipped baseline) |
| **Home** — design under review | `ui-lab/home-v2.2/*` (seven files) | project (source: lab `docs/`) | Pending Review |
| **Home** — newest draft | Home v2.3 (verification in progress; documents not yet issued) | lab | Current Draft |
| **Home** — earlier design rounds | `ui-lab/*` (v2), `ui-lab/home-v2.1/*` | project | Historical (proposed label; not marked Superseded) |
| **Current approved Home specification** | **None.** No UI Lab Home version has been formally approved | — | — |
| **Plan** — shipped behaviour | Code on rel; read-only audit `ui-lab/plan/PLAN_CURRENT_UI_AUDIT.md` | project | Current Draft (audit) |
| **Plan** — design | `product/plan/PLAN_V2_SPECIFICATION.md` v0.6 (+ `product/plan/wireframes/`, `product/plan/visual-v04/`, `product/plan/visual-v05-B/`) | gov | Current Draft |
| **Coach** — automatic adjustments audit and correction plan | `product/coach/AUTOADAPT_AUDIT_AND_CORRECTION_PLAN.md` | gov | Current Draft (plan only) |
| **Coach** — automatic adaptation correction proposal (two code paths; protective reductions) | `product/coach/AUTOADAPT_CORRECTION_PROPOSAL.md` v0.1 | gov | Pending Review (proposal only) |
| **Plan** — UI Lab implementation scope | `product/plan/PLAN_UI_LAB_SCOPE.md` v0.4 | gov | Pending Review (not started) |
| **Progress v2.0** — Phase 0 audit of current Progress | `product/progress/PROGRESS_V2_PHASE0_AUDIT.md` v0.1 | gov | Current Draft (read-only audit) |
| **Progress v2.0** — competitor research and Athlete Evolution framework | `product/progress/PROGRESS_V2_RESEARCH_AND_FRAMEWORK.md` v0.1 | gov | Current Draft (proposal; no thresholds, nothing calculated) |
| **Progress v2.0** — concept directions, landing architecture, Singularity feasibility | `product/progress/PROGRESS_V2_CONCEPTS_AND_FEASIBILITY.md` v0.1 (+ `product/progress/concepts/`) | gov | Current Draft (static concepts; nothing built) |
| **Progress v2.0** — visual design specification: collapsing singularity, full landing page, detail screens, acceptance criteria | `product/progress/PROGRESS_V2_VISUAL_DESIGN_SPECIFICATION.md` v0.3 — adds Part B, Progress v2.2 open-surface design, Variants A and B (+ `product/progress/design-v02/`, `design-v22/`) | gov | Current Draft — awaiting owner approval (static designs; nothing built) |
| **Progress v2.1** — discipline-agnostic architecture (Endurance / Strength / Hybrid), athlete-type and sports audit, label rules, dependencies, acceptance criteria | `product/progress/PROGRESS_V21_ARCHITECTURE_AND_AUDIT.md` v0.1 (+ `product/progress/design-v21/`) | gov | Current Draft — awaiting owner review (static designs; nothing built) |
| **Progress v2.1** — Metric Registry proposal | `product/progress/PROGRESS_V21_METRIC_REGISTRY.md` v0.1 | gov | Current Draft — awaiting owner review |
| **Progress v2.3** — final visual refinement: Evolution Track, four-metric landing page, Next evolution, detail-screen hierarchy, before/after, dependencies, acceptance criteria | `product/progress/PROGRESS_V23_VISUAL_REFINEMENT.md` v0.1 (+ `product/progress/design-v23/`) | gov | Current Draft — awaiting owner visual review (static designs; nothing built) |
| **Progress v2.3** — compact hero: proportional refinement with measurements | `product/progress/PROGRESS_V23_COMPACT_HERO.md` v0.1 (+ `product/progress/design-v23-compact/`) | gov | **Approved as the visual baseline for Progress, 13 Nov 2026** (design approval only; commit `0f38f06`) |
| **Decision** — Progress compact hero approved; Progress UI Lab proof of concept authorised | `decisions/2026-11-13_progress-compact-hero-approved-and-poc-authorised.md` | gov | Decision record |
| **Progress UI Lab proof of concept** — status and evidence | `ui-lab/progress/PROGRESS_POC_STATUS.md` v0.2 | gov | Current Draft — code written on `proto/ui-lab-progress`; first run 43472777501: compiled; 5 of 8 tests passed on standard, 6 of 8 on small; corrections pending owner review |
| **Training Hub v1.0** — Option D: audit, UX architecture, lifecycle, interaction rules, comparison, acceptance criteria | `product/train/TRAINING_HUB_V1_DESIGN.md` v0.1 (+ `product/train/design-v10/`) | gov | Current Draft — Phase 0, awaiting owner visual review (static designs; nothing built) |
| **Metrics** — schedule adherence, training fulfillment, actual volume | `product/metrics/PLAN_ADHERENCE_METRICS_PROPOSAL.md` v0.1 | gov | Current Draft (proposal; nothing calculated) |
| **Plan** — earlier proposal (weekly calendar only) | `ui-lab/plan/PLAN_V1_PROPOSAL.md` | project | Pending Review (not marked Superseded) |
| **Coach** — implemented behaviour | `ios/ADAPTIVE_COACH.md`, `ios/BEHAVIOUR_CONTRACT.md`, `ios/SAFETY_CHANGES_RC3.md` | rel | Current Approved (describes shipped rules) |
| **Coach** — audit of what exists | `planning/adaptive-lifestyle-coach/A_CURRENT_AI_COACH_AUDIT.md` | project | Current Approved (audit accepted with Decisions 1–12) |
| **Coach** — future direction | `planning/adaptive-lifestyle-coach/B…E` + Decisions 1–12 | project | Current Approved as planning; **not implemented** |
| **Coach conversation** (timeline) | Home v2.3 integration map (to be issued) | lab | Current Draft |
| **Onboarding** — implemented | `ios/V1_ONBOARDING_PROFILE_DEVICES.md`, `ios/UI2_CHANGES_RC3.md` | rel | Historical record of what was built (proposed label) |
| **Onboarding** — future | `planning/adaptive-lifestyle-coach/C_ONBOARDING_V2_SPECIFICATION.md` | project | Current Approved as planning; not implemented |
| **Train / Training Hub, Ride** | `ios/RIDE_LAYOUTS.md`, `ios/UX_CHECKPOINT_C_NAVIGATION.md` | rel | Pending Review — no single current specification exists |
| **Progress, Profile** | `ios/UI1_CHANGES_RC3.md`, `ios/UX_UPGRADE_CHECKPOINT_A.md` | rel | Pending Review — no single current specification exists |
| **Strength** | `ios/STRENGTH_AUDIT.md`, `ios/QUALITY_RELEASE.md` | rel | Historical record (proposed label) |
| **Metrics and definitions** | None as one file. Sources: Home integration maps, coach audit A | — | **Gap** — proposed `product/METRICS_AND_DEFINITIONS.md` |
| iPhone design system (production components) | `ios/DESIGN_SYSTEM.md` | rel | Current Approved (describes shipped components) |
| Earlier appearances and grading | `ios/APPEARANCE_AND_GRADING.md` | rel | Pending Review (register 2, 6) |
| Technical architecture — entry page | `architecture/ARCHITECTURE_INDEX.md` | gov | Current Draft |
| Data ownership | `ios/OWNERSHIP.md` | rel | Current Approved |
| Integration architecture (devices) | `ios/INTEGRATION_ARCHITECTURE.md` | rel | Current Approved |
| Data integrity and migrations | `ios/S20_DATA_INTEGRITY.md` | rel | Current Approved |
| Testing and release process | `ios/CI_PROCESS.md` (rules), `ios/CI_PIPELINE.md` (mechanics), `ios/TEST_MATRIX.md` | rel | Current Approved; overlap noted in consolidation proposal |
| App completeness (iPhone) | `iphone-app/APP_COMPLETENESS_AUDIT_BUILD216.md` | project (repo copy `ios/APP_COMPLETENESS_AUDIT.md`) | Current Approved as of build 216 |
| **LILYGO Watch** — design system and screens | `hardware-design/UIUX_V3_DESIGN_SYSTEM_AND_IA.md` | project | A, B: Current Approved · C, D: Pending Review |
| **LILYGO Watch** — features | `hardware-design/FEATURE_REGISTRY_102.md` | project | Current Approved (registry) |
| **LILYGO Watch** — readiness | `hardware-design/WATCH_STAGE2A_READINESS.md`, `WATCH_IMPLEMENTATION_READINESS.md` | project | Current Draft |
| **Detachable system** concept | `hardware-design/DETACHABLE_SYSTEM_PHASE1.md`, `PROTOTYPE_P1_AND_TEST_PLAN.md`, `P1_MEASUREMENT_GUIDE_BOM_ACCEPTANCE.md` | project | Pending Review |
| **Waveshare BikeComputer** — master brief and status | `CYCLIFT_HARDWARE_HANDOVER/01_BIKECOMPUTER_MASTER_BRIEF.md`, `06_IMPLEMENTATION_STATUS.md` | hw | Current Approved (handover of 10 Nov) |
| **Waveshare BikeComputer** — link protocol | `firmware/waveshare/docs/BLE_LINK_PROTOCOL.md`, `docs/LINK_V1_2_SPEC.md` | rel | Current Approved for the versions they name |
| Android app | `android-app/OPEN_ISSUES_PRIVACY_AND_SIGNING.md` | project | Pending Review |
| Legal text | `ios/legal/privacy.md`, `ios/legal/terms.md` | rel | Current Approved (a copy ships inside the app) |
| Project dashboards | `CYCLIFT_WORK_STATUS.md`, `coord/TASKBOARD.md` | rel | Historical (proposed label; last updated 27–28 Oct — see tracker audit) |

## Reference copies in the Claude project

| Project path | Source | Version | Last synchronised |
|---|---|---|---|
| `governance/DOCUMENTATION_INDEX.md` | gov `governance/DOCUMENTATION_INDEX.md` | 0.3 | 12 Nov 2026 |
| `governance/CONFLICT_REGISTER.md` | gov `governance/CONFLICT_REGISTER.md` | 0.3 | 12 Nov 2026 |
| `brand/CYCLIFT_BRAND_BOOK.md` | gov `brand/CYCLIFT_BRAND_BOOK.md` | 0.2 | 12 Nov 2026 |
| `product/plan/PLAN_V2_SPECIFICATION.md` | gov `product/plan/PLAN_V2_SPECIFICATION.md` | 0.6 | 12 Nov 2026 |
| `product/plan/PLAN_UI_LAB_SCOPE.md` | gov `product/plan/PLAN_UI_LAB_SCOPE.md` | 0.4 | 13 Nov 2026 |
| `product/metrics/PLAN_ADHERENCE_METRICS_PROPOSAL.md` | gov `product/metrics/PLAN_ADHERENCE_METRICS_PROPOSAL.md` | 0.1 | 12 Nov 2026 |
| `product/coach/AUTOADAPT_CORRECTION_PROPOSAL.md` | gov `product/coach/AUTOADAPT_CORRECTION_PROPOSAL.md` | 0.1 | 12 Nov 2026 |

Documents that today exist **only** in the project (UI Lab sets, coach planning A–E, decisions, hardware-design files)
have no GitHub source yet. Bringing them onto this branch is a **migration step that waits for approval**.

## Limits

Read for this index: all project documents (by title and, for the governing ones, content), the release branch's
documentation, and the hardware-handover branch's file list and design-system file. Documents existing only on other
branches (51 branches in total) were not opened individually.
