# Home v2.1 — revision record (UI Lab prototype)

**Owner instruction:** "Home v2.1 — approved UI/UX revision instructions", 12 Nov 2026 (isolated UI Lab only;
production integration not authorised). A WHOOP dashboard screenshot was supplied afterwards as a density reference.
**Evidence level:** compiled and captured in the simulator by the prototype's own pipeline — final run 43108414885,
commit `05e1202` (iOS 26.5 simulator; iPhone 17 and iPhone SE 3rd generation). Not checked on a physical iPhone;
VoiceOver not listened to. **Nothing is approved; nothing is integrated.**

## Before / after

| Area | Home v2 (reviewed 11–12 Nov) | Home v2.1 |
|---|---|---|
| Header | Date line + large "Good afternoon, Alex" (two lines at large text) | One small line (date · athlete type) and the name on one line; avatar unchanged |
| Indicators | Three similar rings in a bordered card: Consistency, Load Balance (full ring + tick), Recovery (full ring + tick) | Borderless row: Consistency gradient ring · **Training Mix** double ring (outer endurance, inner strength, separate values) · Recovery as three availability arcs with an icon and a word — no full ring, no tick, no percentage |
| "Load Balance" | Middle Home indicator | Removed from Home. The load analysis itself is untouched and remains a separate analytics capability |
| Schedule | Card, 60 pt cells, icons plus a status tick under each day | Borderless, about 50 pt; status is carried by the session mark itself (filled, outline, dashed + slash, arrow); no ticks |
| Sport cards | Tall: total, bar, secondary metric, sparkline, caption; "Strength Load" | Compact: done / planned, thin bar, one metric; sparkline and history moved to the detail sheet; titled "Strength" |
| Sleep | — | New borderless bar: last night, bar (last night ÷ target), 7-day average, target; detail sheet with source and freshness |
| Coach | Three equal compact buttons | Review is the primary action; Not now is quiet text and postpones; Why? is a small action; accepted / declined / postponed are shown as three different outcomes |
| Trends | Consistency line + Load Balance row + Recovery row + chips + paragraph | One chart of training minutes (endurance and strength stacked, planned as a faint bar), 7 days / 4 weeks, touch a day for a tooltip and a daily sheet; methodology moved to an info sheet |
| Metrics | — | "Key metrics": dashboard rows (name, value, own comparison value, neutral direction marker), each tappable; two-column grid kept as an alternative with a Lab switch |
| Getting Started | Checklist card (expanded at top, collapsed card at the bottom) | Compact card with the next required action while a required step is open; one quiet line when complete; Required / Optional tags |
| Navigation | Fixed tab bar | Floating capsule with a sliding highlight and raised centre action, modelled on the app's existing dock; soft fade so content does not show sharply beneath it |
| Surfaces | Border on every card | No card outline on dark themes, a hairline on light themes, full borders only in High Contrast; restrained gradients on rings, bars and the coach surface (flat in High Contrast) |
| Scenarios | Established, new user, loading | Plus cycling only, strength only, no planned sessions, no Apple Health / partial sensors, long name |

Home length at the default text size on iPhone 17: the first screen now reaches the Coach card; v2 ended at the
sport cards.

## Requirements not implemented faithfully, and why

| # | Requirement | State | Reason |
|---|---|---|---|
| 1 | "Restore the original floating navigation" | Modelled on it, not the same code | The prototype may not share production code; the dock was rebuilt from a read-only look at the app's `CyLiquidDock` (capsule, material, sliding pill with a slight stretch, raised centre). Small visual differences are possible and need the owner's eye |
| 2 | "Double ring inspired by the approved Cyclift Watch interface" | Built from the written description | The Watch artwork itself was not opened in this workstream (hardware design belongs to another conversation); ring order and colours follow the instruction text |
| 3 | Metrics "prioritised for the athlete's sports, goals and connected data" | Sample sets per scenario only | The selection rule is integration work; the prototype shows different sets for hybrid, cycling-only, strength-only and partial-data athletes |
| 4 | Sleep "recommended or user-selected target" | Sample target, labelled as such | No target exists in production and none may be invented; the component takes a target and its source as inputs |
| 5 | Trends "training load, where available" in the day detail | Not shown per day | The sample holds weekly load only (Key metrics); a per-day load was not invented |
| 6 | "Test local prototype interactions" / "chart touch interactions" | Verified by launching each state and sheet directly and by screenshot; **not by automated taps or by hand** | The lab has no UI-test target and cannot be used hands-on from here. Each interactive element is wired to a local action in code and every sheet was captured, but tap-through behaviour has not been exercised by a person |
| 7 | "Preserve the existing accessibility and component test infrastructure" | Kept and passing (token contrast check: 294 pairs, 0 failures); no test was removed or loosened | Gradient tails on bars and rings fade below the token's checked contrast by design; the full-colour head of each bar or arc remains at the checked value |
| 8 | Full-length Home screenshots | Provided, with one artefact | They are rendered by the prototype itself as one tall image: the floating dock is not included, and ring arcs start from a different angle than on screen. The normal screenshots show the true on-screen appearance |
| 9 | Hands-on experience on the owner's iPhone | Not available | Needs a separate prototype app on TestFlight, which is not authorised |

## Open design questions for the owner's review

1. Key metrics: rows (reference style) or the two-column grid?
2. Direction markers are neutral grey rather than coloured good / bad — keep neutral?
3. Monday in the sample shows two marks (a completed strength session and a missed ride); are the marks clear enough at this size?
4. Recovery indicator: are three "which readings exist" arcs the right qualitative picture?
5. At large text the date line wraps and the "SAMPLE" tag sits beside it (the tag is prototype-only).
6. High Contrast keeps full borders and flat colours — acceptable as the legibility-first theme?
