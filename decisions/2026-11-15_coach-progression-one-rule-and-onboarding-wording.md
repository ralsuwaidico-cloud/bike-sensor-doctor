# Decision — One Coach progression rule across the product; onboarding wording corrected

**Date:** 15 Nov 2026 · **Decided by:** owner (clarification of 15 Nov and the Final Development Alignment and E1 Readiness Directive, sections 4 and 5) · **Status:** decided direction — **not implemented, not tested.**

## The rule

1. AI makes assessments and proposals. An independent policy engine authorizes any automatic action.
2. **Small increases in load or repetitions** may be applied automatically **only** when the independently validated policy engine explicitly authorizes them.
3. **Increases in sets, intervals, ride duration or other training load require athlete approval**, unless separately authorized in a future policy.
4. Protective actions may be automatic only under an explicitly approved safety-rule allowlist (still pending — conflict register item 34).
5. Every automatic change has a reason, an evidence reference, a policy version, a recorded outcome and a reversal path.
6. AI-generated suggestions never bypass policy validation. If AI is unavailable, validated existing rules continue; no unapproved AI-derived automatic progression occurs.
7. The same training change must not be applied independently by two engines.

## Interim safeguard (planning requirement for E1; not yet authorized as code)

Until the policy engine exists, the app must not silently apply increases to sets, intervals or ride duration. They are held as proposals requiring athlete approval. Both existing paths are covered: the adaptive Coach (`autoAdapt`, on by default) and the strength planner's rebuild logic. Planned as E1-PR11 in `release/e1-readiness-2026-11-15/`.

## Wording that replaces "Increases always need your approval"

Onboarding page 5 and wherever the Coach preference is described (Blueprint page 7, Profile › Coach preference, Coach page):

> **Your Coach can make small adjustments to reps and load when approved safety rules allow it.** Other increases are presented for your approval. You can review why your plan changed.

Preference control: **Small steps for me** (default) · **Always ask me**. The control carries over the preference that already existed on page 5 in v3.1–v3.3; "Always ask me" turns automatic small steps off. Whether the control is kept is listed for the owner as D-C0 in the readiness package.

**No onboarding promise ships unless the app fulfils it:** this wording may appear in a build only together with the policy engine (C0). In build E1 the existing screens stay, and the behaviour is "all increases are proposals".

## What this supersedes, on this point only

| Document | Passage | Status on this point |
|---|---|---|
| Conflict register 26, 32, 69, 83 ("increases require approval") | Standing direction of 12 Nov | **Refined** — items 84 and 86 |
| `product/onboarding/v33/ONBOARDING_V33_EXPERIENCE_REFINEMENT.md` §6.1 | "Page 5 says increases always need approval" | **Corrected** — note added in the file |
| `product/onboarding/v33/ONBOARDING_V33_INTEGRATION_CONTRACTS.md` (Coach auto-adjustment row) | same | **Corrected** — note added in the file |
| `product/plan/PLAN_V2_SPECIFICATION.md` decision 10, rule R6, §11 | "Automatic increases in load, volume or frequency require approval" | **Refined** — note added in the file; volume and frequency still require approval |
| `release/consolidation/rev2/C_BASELINE_REGISTER_rev2.md`, `H_APPROVAL_CHECKLIST_rev2.md` | "increases need approval" | **Refined** — read with this record; files not edited |
| Onboarding v3.0, v3.1, v3.2; Coach architecture v1 | same | Historical / superseded — not edited |
| Coach + Fueling design review v2 | Policy registry P-REP-1, P-LOAD-1/2 | **Consistent** with this rule; its numeric limits remain proposed (D-C1) |

Not decided here: the numeric limits of a "small" step; the protective allowlist; any implementation.
