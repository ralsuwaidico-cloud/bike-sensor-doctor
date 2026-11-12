# Discipline colours — production migration impact assessment

Status: Current Draft · Version 0.1 · 12 Nov 2026
**Assessment only. No migration is authorised and nothing was changed.** Figures are counts of text matches in the
Swift source on the release branch (`ios/checkpoint-f-ride`, commit `4e2e9dc`), taken read-only.

## 1. The decision being assessed

Future six-theme development uses: endurance blue / cyan · strength amber / warm orange · recovery green · status
colours independent of discipline colours (Brand Book §4.5).

## 2. Where production stands

| Meaning | Production today | Direction | Change |
|---|---|---|---|
| Cycling / endurance | `CyTheme.cycling` indigo-blue (#3550B5 light, #A9BAF5 dark) | Blue / cyan | Hue shift within blue — small |
| Strength | `CyTheme.strength` **rose** (#A3324F light, #F2A9BB dark); older `BC.strength` **purple** | Amber / warm orange | **Large, visible change** |
| Recovery | `CyTheme.recovery` green | Green | None in meaning |
| Goal | `CyTheme.goal` **amber** (#855400 / #F3D088) | (not in the direction) | **Collision**: amber would mean both "goal" and "strength" |
| Insight / coach | `CyTheme.insight` violet | (not in the direction) | None, but the UI Lab uses violet for the recovery ring |
| Warning | `CyTheme.warn` orange-brown (#9A4B00 / #F5B97A); `BC.stale` amber; `BC.sim` orange | Independent of discipline | **Collision risk**: strength amber vs warning amber |
| Success / "ok" | `CyTheme.ok` **is** `recovery.tint`; `BC.live` green | Independent of discipline | **Coupled today**: success is literally the recovery colour |

## 3. Size of the change in code (read-only counts)

| Token | Uses | Files |
|---|---|---|
| `CyTheme.cycling` | 34 | 12 |
| `CyTheme.strength` | 15 | 8 |
| `CyTheme.recovery` | 28 | 11 |
| `CyTheme.goal` | 12 | 5 |
| `CyTheme.insight` | 12 | 5 |
| `CyTheme.identity(…)` (indirect) | 12 | 5 |
| `CyTheme.ink…` (text colours) | 201 | 14 |
| `CyTheme.canvas` | 27 | 11 |
| `BC.accent` (older set) | 139 | 23 |
| `BC.warn` · `BC.stale` · `BC.live` | 64 · 58 · 49 | 21 · 22 · 19 |
| `BC.zone(…)` (seven training-zone colours) | 25 | 9 |
| `BC.strength` | 1 | 1 |
| System grouped backgrounds (not theme-aware) | 43 | 8 + 8 |

Of 111 Swift files in the app target, 18 use `CyTheme` and 31 use the older `BC` set.
`CyTheme` and `BC` colours are defined once each, so **changing the discipline hues alone is a small edit in one file** —
the cost is in what it touches, not in the number of lines.

## 4. What a migration would affect

| Area | Impact | Why |
|---|---|---|
| Strength everywhere (cards, chips, charts, Plan timeline, Progress) | High, visible | Rose → amber changes the look of every strength element |
| Goal indicators | Must be re-coloured or re-thought | Amber is taken by strength in the direction |
| Warnings and "stale" states | Must be checked for confusion with strength | Both amber-family |
| Success vs recovery | Needs separate tokens | Today `ok` = recovery tint |
| Training-zone colours (`BC.zone`) | Review | Seven fixed hues; some overlap the new discipline hues (zone colours are a separate meaning and should stay separate) |
| Screens still on the older `BC` set and system backgrounds (31 files; Plan among them) | These do not follow any theme today | Six themes cannot reach them without converting those screens first — a much larger job than the hue change |
| Light / dark only | Production has two palettes; six themes need a theme model the app does not have | The token-injection foundation was lost with the unpushed appearance branch (decision 10 Nov §4) |
| Apple Watch app | 4 colour uses | Small |
| Detachable Watch | No values for the six themes | Register 13 |
| Waveshare BikeComputer firmware | Its own colours (18 literals in firmware source) | Separate workstream; not interchangeable |
| Automated layout and design audits | Contrast must be re-proven per theme | Screenshots and contrast checks are part of release evidence |
| App Store screenshots, marketing | Would no longer match | Outside code |
| Data, engines, protocols | **None** | Colour only |

## 5. Risks

1. Strength / warning / goal confusion if amber is used for all three.
2. A half-migration: `CyTheme` screens in new colours next to `BC` screens in old ones.
3. Contrast regressions in light themes — amber on white needs the darker values the prototype already uses.
4. Colour-blind distinguishability of blue vs green vs amber is better than rose vs indigo, but must be checked with icons and labels, which stay mandatory.

## 6. A possible order, if ever authorised (not a plan of record)

1. Assess the three component systems (`CyTheme` components, `BC` / `DS` styles, UI Lab library) — the same assessment the typography and spacing decision waits for.
2. Introduce a theme model with the two existing palettes expressed as themes — no visual change.
3. Separate `success` from `recovery`, and decide goal and warning hues.
4. Convert the remaining `BC` screens to tokens, page by page, with the page redesigns already planned.
5. Only then switch discipline hues and add the six themes, behind the existing simulator audits, with a physical-device review.

## 7. Limits

Counts are text matches, not a semantic analysis; a token passed through a helper is counted once at the call site.
Nothing was compiled or run. Firmware sources were counted, not reviewed.
