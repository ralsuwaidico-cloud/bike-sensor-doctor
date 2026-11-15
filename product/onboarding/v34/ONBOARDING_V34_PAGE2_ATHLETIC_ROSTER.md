# Cyclift — Onboarding v3.4 — Page 2 only: the Athletic Roster

**Version:** 0.1 · 15 Nov 2026 · **Status:** Design proposal — **Pending Owner Visual Approval**. **Implementation NOT AUTHORIZED.** Static drawings only: nothing implemented, compiled, run or tested; no prototype. **ILLUSTRATIVE DESIGN — NOT IMPLEMENTED.**

**Owner direction recorded (15 Nov):** the v3.3 seven-page structure remains the current design direction; **v3.3 Page 2 is not visually approved.** Only Page 2 is redesigned here. Pages 1 and 3–7 are not edited; proposed impacts on them are listed in §8. v3.3 documents are unchanged.

## 1. The idea
One hierarchy, read top to bottom, in which every sport appears once:
1. **Main sport(s)** — the athlete's identity in large type. One main sport, or one endurance and one strength sport with a **lead** setting.
2. **Also training** — other sports in the roster, one row each, with "Make main" and remove.
3. **Add to your roster** — a few suggestions Cyclift can plan and record, in the same rows, until the athlete's own rows replace them.
4. **Browse all activities** — the single entry to the library: search, four categories, grouped by capability.
Recovery interests are one summary line, however many are chosen.

No dial, slider, card grid, constellation, duplicate chip row or score. Controls: rows, one segmented control, one sheet.

## 2. States
| Sports | What the page shows |
|---|---|
| None | A headline ("Start with the sport you train most."), four sports Cyclift can plan and record as suggestion rows, then Browse. No empty slots are drawn. Continue unavailable |
| One | That sport as main, marked "suggested · Continue confirms"; suggestions below |
| Two (endurance + strength) | Two main sports and the lead control, default Balanced |
| Three and more | Further sports under "Also training" |
| More than fits | Three rows (two on a small iPhone) and "n more in your roster", which opens the library on the selection. The page never grows |
| Unsupported only | "No planned sport yet"; the chosen sports are kept and labelled; cycling and strength are suggested; Continue unavailable |

## 3. The main-sport rule
- The first plannable sport chosen is **suggested** as main and labelled so. The athlete confirms by continuing, or changes it with **Make main** on any plannable row; the two sports swap places.
- One main sport per domain (endurance, strength). A sport Cyclift cannot plan has no "Make main".
- With both domains present the lead control offers **Endurance-led · Balanced · Strength-led**. These are the three existing stored priority values (`cycling`, `balanced`, `strength`) with type `hybrid`; no proportion or percentage exists or is shown. The led sport is listed first and in full weight; in Balanced both are equal.
- × on a main sport removes it; if the other domain then has no sport, the type returns to cycling or strength and the lead control disappears.

## 4. Capability — four kinds, always in words
| Mark | Meaning | Activities drawn | May be main |
|---|---|---|---|
| ● | Cyclift plans and records | Road cycling, Gym training | yes |
| ◐ | Recorded with a recorder Cyclift already has (planned as cycling or strength) | Indoor cycling, Mountain bike, Bodyweight | yes |
| ◌ | Not supported yet — saved as interest | Running, Swimming, Walking | no |
| ○ | Recovery interest — not training | Stretching & mobility, Breathing, Sauna & cold | no |
Source: activity registry as read in build 216 (cycling types share one recorder; no indoor mode; bodyweight recorded as strength — its identifier is still open). Appearing in the library grants nothing. Commuting and Other exist in storage and would be reached by search; they are not drawn. Selected sports and declared experience never affect an Athlete Evolution stage.

## 5. The library
A sheet over Page 2 (not a page): search, categories All · Endurance · Strength · Recovery, rows grouped under the four capability headings, tick to select, "Done · n". Search narrows the same list. Nothing typed is saved as a sport.

## 6. v3.3 → v3.4 (same device, same selection — sheet Z1)
| | v3.3 Page 2 | v3.4 Page 2 |
|---|---|---|
| Hierarchy | Line-up of circles, then twelve chips in three groups | Main → also → suggestions → library |
| Each sport appears | Twice when chosen (circle and chip) | Once |
| Choices always on screen | 11 activities + "More" | Up to 4 suggestions; the rest in the library |
| Main sport | Large circle; changed by tapping a circle | Large type; "Make main" written on the row |
| Lead / priority | Asked on Page 3 | On Page 2, beside the sports it concerns |
| Capability | Solid vs dashed, one legend | Words on every row; four kinds |
| Many sports | Circles truncate at six | Fixed rows + "n more" |
| Selected state | Chip fill | Row moves from suggestion to roster, gains × |
| Accessibility | Small chips; state partly by fill | 52 pt rows; names wrap at large text; every state has words |

**Taps, counted from the drawings (not measured with users):**
| Selection | v3.3 | v3.4 |
|---|---|---|
| Road cycling only | 1 | 1 |
| Road + Gym, balanced | 2 (+ priority on Page 3: 0) | 2 |
| Road + Gym + Indoor | 3 | 3 |
| … + Running + Stretching | 5 | 7 (open library, two ticks, Done) |
| Change main sport | 1 | 1 |
**Trade-offs:** unsupported sports and recovery interests cost two extra taps because they live in the library; fewer activities are visible at once; when a suggestion is taken the rows below it can shift by one place; the first selection changes the top of the page from a headline to the roster (one deliberate change of layout).
No benefit has been tested. These are design arguments, not results.

## 7. Movement (described; works without it)
A chosen suggestion moves up into the roster (about 200 ms); main sports cross-fade when swapped; the lead control fades in. With Reduce Motion every change is an immediate replace. Nothing depends on the animation to be understood.

## 8. Effects elsewhere (documentation only — no other page edited)
| Where | Effect | Status |
|---|---|---|
| Page 3 Goals | Goal groups follow the stored type (as build 216). "When time is short, protect" would be **removed** from Page 3 — the lead is set here | proposed change to v3.3 Page 3 |
| Page 4 Week | Day editor offers the roster's plannable sports; main sport proposed first; lead decides the proposed mix (existing rule) | sport type per session is a new field |
| Page 7 Blueprint | Identity line "Road cycling + Gym training · balanced" would replace the circle line-up | proposed change to v3.3 Page 7 |
| Profile › My Activities | Same roster, same controls; one stored copy | Profile v2.0 visuals still pending |
| Training Hub selector | "Your activities" = selected ∩ selectable; main first (Hub v1.1 §6); unsupported shown as not recordable | main flag new |
| Coach | Recommends only cycling and strength sessions; a mobility plan entry exists without a recorder | today |
| Progress | Roster shows or hides discipline sections only; evidence alone sets a stage | section visibility is designed, not implemented |

## 9. Model
Preserved: `trainingMode` (cycling / strength / hybrid), `priority` (cycling / balanced / strength), `sports`.
Additions (additive, none exist today): **main-sport flag per domain** (register 77); identifiers for Walking and the three recovery interests; Bodyweight identifier or mapping (open). "Suggested / confirmed" is not stored. No migration designed or tested.

## 10. Open
1. Arabic strings are illustrative and need native review; no Arabic typeface is chosen.
2. Whether a ◐ sport (indoor, mountain bike, bodyweight) should be allowed as main — drawn as allowed.
3. Suggestion order after the first pick (drawn: other domain first, then shared-recorder sports).
4. Coach auto-adjustment contradiction (register 69) and stage rules (register 74) are unchanged.
5. Not drawn: Ocean, Forest, Sandstone, High Contrast for this page; library at large text; the "n more" view; error and loading states.

## 11. Sheets (`sheets/`)
Z1 v3.3 and v3.4 · Z2 progression (0, 1, 2, 3, many) · Z3 library · Z4 journeys · Z5 Arctic, small iPhone, large text, right-to-left · Z6 effects elsewhere.
