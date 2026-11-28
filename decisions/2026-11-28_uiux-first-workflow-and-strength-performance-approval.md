# Decision — UI/UX is completed and approved before detailed functionality; Strength Performance Revision 1.1 approved and locked

**Date:** 28 Nov 2026, 11:47 (Dubai) · **Decided by:** owner · **Recorded by:** Claude · **Status:** approved, in force.

## 1. Workflow

The current objective is to complete and approve the entire Cyclift UI/UX before addressing detailed functionality. From this point every review is separated into two parts.

| UI/UX approval | Functional development backlog |
|---|---|
| Visual hierarchy · layout · components · navigation · user interactions · information presentation · empty and missing-data states · intended user experience | Calculation methodologies · algorithm validation · data storage · sensor integrations · activity recording and importing · scheduling support · Coach intelligence · data migrations · functional defects · regression testing |

Rules, in the owner's words:

- "Do not allow unresolved functionality decisions to unnecessarily delay UI/UX approval."
- "Design the intended complete experience, not merely an interface restricted to what the current code supports."
- "Use clearly identified illustrative data to demonstrate future functionality during design reviews."
- "Do not reopen approved screens unless a material UI/UX conflict is identified."

What does not change: an approved interface is never proof that a feature works; illustrative data is always labelled as such and never presented as measured; no production merge, TestFlight upload, firmware change, external AI activation or athlete-data transmission without explicit approval.

The functional backlog is `release/FUNCTIONAL_DEVELOPMENT_BACKLOG.md`. The UI/UX status of every screen is `docs/design/CYCLIFT_UIUX_APPROVAL_TRACKER.md`.

## 2. Strength Performance

Strength Performance v1.0 Revision 1.1 is approved and locked as the official Strength Performance UI/UX reference: page hierarchy, graphs, expandable analytics, muscle map, progressive overload, activity cards, workout history and navigation architecture.

Nine minor refinements, needing no further approval cycle unless they materially change the approved design:

1. The current anatomical muscle-map illustration is accepted; muscle regions and their selection states stay clear and accessible.
2. Three primary figures: Sessions, Working sets, Plan completed.
3. Completed sessions, saved records and records awaiting review stay distinct.
4. The four plan-matching presentation states are accepted; the matching criteria are deferred to the functionality phase.
5. The complete muscle-group analysis UI is retained, including target ranges as designed future-state functionality.
6. Lengthy calculation explanations and technical warnings move into information controls where appropriate.
7. Terminology, typography, spacing and measurement states stay consistent with the approved Endurance Performance page.
8. Dynamic strength activity cards for all relevant strength disciplines, not only conventional gym training.
9. The self-contained analytical navigation rule is preserved.

Reference: `docs/design/proposals/strength-performance-v1/Cyclift_Strength_Performance_Approved_UI_Reference.pdf`; register entry APP-10. The Revision 1.1 review PDF, the v1.0 exploration and the exercise-mapping workbook are preserved unchanged.

**Not approved by this decision:** any calculation method. Twelve Strength requirements were transferred to the functional backlog and are "not to be implemented or finalized now".

**Not implemented:** the approved design exists as mockups with illustrative data. The page running in the app is still the older "Strength summary".
