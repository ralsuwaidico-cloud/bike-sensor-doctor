# D — Corrected Integration and Data Flow (revision 2)

**Revision 2 · 15 Nov 2026 · Status:** Corrected consolidation — **Pending Owner Final Review. No implementation authorized.** Read-only: no code, data, branch or distribution change. Drawings are static; none is simulator or device evidence. Revision 1 documents are kept unchanged in the parent folder. Ownership table and diagrams of revision 1 stand. This revision states each influence the walkthrough shows, with what is true today.

| Influence | Stored value | Where it shows (sheet) | True today | Needed |
|---|---|---|---|---|
| Chosen sports → available activities | `sports`, main flag (new) | Train panel quick-starts, selector (G3) | No — `sports` is read by no engine; hub derives from type | Capability table; main flag (U1/U2) |
| Chosen sports → disciplines planned | `trainingMode` (derived) | Plan, Home (G3) | Yes, via type | Derivation from roster (U1) |
| Training priority → planning | `priority` | Proposed week (G2), Plan (G3) | Yes | Single owner on Page 2 (U1) |
| Goals → Coach | goals, primaryGoal | Blueprint, program line (G2, G3) | Yes (one effective goal per sport) | — |
| Available days → schedule | availability | Week, Weekly Calendar, Recurring Plan | Yes | Per-day lengths verified (U1) |
| Sensors → metrics | paired devices | Cycling shows power only with a power meter (G4) | Yes | Wording of lost sensor (U2) |
| Recorded training → Progress | rides, strength logs | Progress sections (G4) | Partly (existing metrics) | New layout; no stage (U3) |
| Review → Coach proposals | effort, performance | Proposal after the review (G5) | Partly — inputs exist; small increases are applied without asking | Approval gate (E1) |
| Proposal approved → Plan | planVersions | Updated Plan with Undo (G5) | Partly — history and undo exist; journey test failing | Fix (E1); screen (U3) |
| Profile change → everywhere | same fields | Profile (G3) | Yes for values; week and type applied without preview | Preview and approval (U1) |
Unsupported capabilities are shown as such: interests "not planned or recorded"; recovery options "design-only"; cycling minimise "blocked".
