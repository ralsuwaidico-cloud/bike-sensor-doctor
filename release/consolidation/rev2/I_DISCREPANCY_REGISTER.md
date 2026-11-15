# I — Discrepancy Register

**Revision 2 · 15 Nov 2026 · Status:** Corrected consolidation — **Pending Owner Final Review. No implementation authorized.** Read-only: no code, data, branch or distribution change. Drawings are static; none is simulator or device evidence. Revision 1 documents are kept unchanged in the parent folder.
Classes: WV wrong visual · WB wrong behaviour · MF missing feature · MI missing integration · IS incorrect implementation status · UA unresolved approval · IC incorrect capability claim.

| # | Area | Agreed requirement | Authoritative reference | Revision 1 interpretation | Actual app (build 216, as read) | Class | Correction |
|---|---|---|---|---|---|---|---|
| 1 | Navigation | Train ball left, cradle, Home/Plan/Progress, no Profile tab | Navigation v1.2 rev 1.1 | Plan, Coach, Train, minimised frames kept the old dock; Progress had none | Five numbered pages, centre button, Profile tab | WV | One dock on every applicable screen (G1–G5) |
| 2 | Navigation | Hidden dock only where the architecture says so | Training Hub v1.4 | Not stated | Ride screen owns its bottom controls | WV | Each full-screen frame labelled and justified |
| 3 | Navigation | Emblem unapproved | Navigation v1.2 | Old "Shift"-like mark visible in Train frames | Dumbbell-style centre button | WV | Dashed-ring placeholder everywhere, labelled |
| 4 | Navigation | Profile from Home avatar | Decision D; v1.2 | Shown, but Home quick-menu retirement not tracked | Quick menu exists | MF | Function NAV-02.3; decision listed in H |
| 5 | Progress | No manufactured stage | Owner rulings 13–15 Nov; criteria not approved | Illustrative G2 with a caveat in small print | No stages in production | WV | Unevaluated state drawn; PRG-03.2, PRG-04.5 blocked |
| 6 | Progress | Interpretive labels need a documented method | Progress v2.1 ruling | "Improving", "Developing Hybrid" shown | — | IC | Removed; PRG-04.4 proposed, not approved |
| 7 | Progress | Proof-of-concept defects preserved | PROGRESS_POC_STATUS | One tracker row | Lab branch only | IS | Three defects tracked separately (PRG-02.3–02.5) |
| 8 | Onboarding | Page 3 without priority; Page 7 identity line | Decision 15 Nov | Drawn | Priority on stage A | — | Kept |
| 9 | Onboarding | Shared-recorder sports are not independent capabilities | Decision 15 Nov | Stated in text only | Names only | IC | Tracker ONB-10.1 not offered; register C item 9 |
| 10 | Onboarding | Sensors chosen affect metrics | v3.3 contracts | Not shown | Works by sensor presence | MI | Journey: power shown because a power meter is paired (G4) |
| 11 | Home | Do not discard earlier Home decisions | Owner decisions 12 Nov | "No approved Home design" only | Production Home | UA | History and open decisions in C rev 2 §Home; functions HOM-01.3–03.2 |
| 12 | Home | Coach preview text-only, timeline page | Project Instructions §7 | One row | Proposals list | MF | HOM-03.1, HOM-03.2, COA-07.2 |
| 13 | Plan | Weekly Calendar and Recurring Plan distinct | Plan v2.0 | Drawn with unrelated program data | Older Plan | WV | Same athlete's week in both views |
| 14 | Plan | Goals, programs, missed sessions, availability, approvals, undo traceable | Plan v2.0 decisions | Eight broad rows | Partly | MF | 22 Plan functions incl. scope of edits, linked replacement, safeguard, single Coach row |
| 15 | Plan | Completion ring and next-session card removed | Decision 12 Nov | Not tracked | Present today | MF | PLN-01.4 |
| 16 | Training Hub | Sets, supersets, rests, loading types | v1.4 | One "strength recorder" row | Long-form logger | MF | TRN-03.1–03.6; supersets marked new capability |
| 17 | Training Hub | Quick-start and recovery entries truthful | v1.4; registry | Shown without status | No recovery recorder | IC | Captions and TRN-08.1 deferred |
| 18 | Training Hub | Cycling map and metrics | v1.4 | Focus only | Current Ride screen | MF | Map and sensor-lost frames added; TRN-06.2 |
| 19 | Training Hub | Review unanswered by default | v1.4 | Stated | Old path has defaults 7 / 6 | WB | TRN-11.1–11.3; COA-07.1 |
| 20 | Profile | Every setting with store and readers | Profile v2.0 function map | Seven rows | Partly | MF | 26 Profile functions with stored value |
| 21 | Profile | No duplicate ownership with Plan | Profile v2.0 | Mentioned | Week and goals edited in Profile, applied directly | WB | PRF-03.1, PRF-08.4 |
| 22 | Profile | Height | Onboarding audit | Not tracked | Stored, no editor | UA | PRF-01.3 decision |
| 23 | Coach | Functions tracked separately | This instruction | Six rows | Rules engine | MF | 22 Coach functions |
| 24 | Coach | Increases need approval | Decision 12 Nov | One row | Two code paths apply or raise loads | WB | COA-03.1–03.5 blocked until corrected (E1) |
| 25 | Coach | Rules-based vs future AI | Project Instructions | Stated | No AI | — | COA-06.1 not planned |
| 26 | Data | Journey data consistent | — | Mixed samples; strength frame showed 22.5 kg against a 20 kg target | — | WV | One dataset; Wednesday at 20 kg, proposal to 22.5 kg |
| 27 | Release | Coherent UX builds | This instruction | Milestone builds mixing generations | — | WB | E/U build split and per-tab map (E rev 2) |
| 28 | Status | Evidence types distinct | Master instructions §11 | Some rows "verified" on journey evidence only | — | IS | Each function carries its own evidence; "verified" only where a run or named test covers it |

Not corrected, and stated: Arctic Progress in the unevaluated state is not drawn (the approved set has that state in Obsidian only); Plan frames use the 402-pt frame by widening the original 393-pt drawing; Home content is a schematic because no Home design is approved; Mobility and Stretch quick-starts remain visible in the approved Train panel drawing and are captioned design-only.
