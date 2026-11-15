# Onboarding v3.0 — integration and ownership matrices

**Version:** 0.1 · 15 Nov 2026 · **Status:** Current Draft — proposal for owner review · nothing implemented
"Current support" is as read in code at `4e2e9dc` (not run). Profile locations use Profile v2.0 sections A–F. Stored names are existing fields unless marked *new*.

## F + G. Question → stored value → Profile location → consumer → current support → intended behaviour → dependency
| Ch. | Question | Stored value | Profile location | Product consumer | Current support | Intended behaviour | Dependency |
|---|---|---|---|---|---|---|---|
| 1 | Name | `profile.name` | A › Personal details | Home greeting, Profile | asked today | same | — |
| 1 | Date of birth | `dateOfBirth` (+ legacy `birthYear`, `age`) | A › Personal details | estimated max HR, zones | asked today | same | one age accessor |
| 1 | Height | `heightCm` | A › Personal details | none | field exists; no editor; no reader | stored and shown only | editor |
| 1 | Weight | `weightKg` + provenance | A › Personal details | W/kg, energy | asked today | same; history never restated | — |
| 1 | Units | `settings.units` | E › Units | all displays; BikeComputer copy | Profile only | asked once in setup | — |
| 2 | Activities | `sports` (+ *new* values) | A › My activities | Train (which activities are offered); Progress (which evidence is shown); Plan (eligibility) | stored; **read by no engine** | drives availability and display; never creates sessions for unsupported sports | registry; engine wiring |
| 2 | Recovery activities | *new* list | A › My activities | Train rest-day shortcuts | none | preference only until a timer/log exists | recovery record type (Training Hub pending item 5) |
| 3 | Emphasis | `trainingMode` | A › Athlete type | Plan, goals, week builder, devices shown | asked today as a three-card choice | suggested from activities, confirmed | — |
| 3 | Protect when short | `priority` | A › Hybrid balance | Plan | asked today | same | overlaps `hybridGoal` |
| 3 | Riding experience | `level` | A › Experience | Plan | asked today | same; never written by Progress | — |
| 3 | Lifting experience | `strengthPrefs.experience` | A › Experience | strength planner | asked today | same; one editor | remove duplicate editor |
| 3 | Goals, main goal | `goals`, `primaryGoal` (→ `goal`, `strengthPrefs.goal`) | Plan (link in B) | Plan; Progress goal context | asked today; one effective goal per sport | same, stated honestly | Plan-owned goal editor |
| 4 | Where you ride | *new* | C › Cycling parameters | Train template (GPS or not) | none; no indoor mode | preference; informs recording template later | indoor handling |
| 4 | FTP | `ftpW`, source, date | C › Power | Plan targets, Train zones, BikeComputer | asked today | same; unknown stays unknown | — |
| 4 | Equipment | `equipment` | B › Equipment & restrictions | strength planner | presets asked today | same | — |
| 4 | Exercises to avoid | `strengthPrefs` exclusions | B › Equipment & restrictions | strength planner, Coach | Profile only | also in setup | — |
| 4 | Supersets, split | `prefersSupersets`, `strengthSplit` | B › Strength preferences | strength planner | supersets asked; split Profile only | same | — |
| 5 | Week, lengths, two-a-day | `availability` (+ kept-in-step profile fields) | Plan (link in B) | Plan, Home upcoming, Coach | asked today | same; rest days worded as planned | Plan-owned schedule editor |
| 5 | Days can move | *new* flag | B › Training Setup (with schedule link) | Coach proposals | none | Coach may propose swaps; approval still required | Coach rules |
| 5 | Rest-day preference | *new* | B › Recovery preference | Train rest-day panel | none | "nothing planned" or optional suggestions | recovery activities |
| 5 | Pause (illness, injury, travel) | `trainingPause` | B › Training pauses | Plan, Home, Coach safety | exists (reasons: unwell, injured, away); not in setup | explained, not asked | — |
| 6 | Apple Health, Watch, BikeComputer, sensors | settings + system permission | D | Train recording; Home recovery information; Progress | device cards exist | same; permission only on tap | — |
| 7 | (no question) Coach introduction | — | E › Coach | Coach | rules-based proposals and approval exist; automatic increases on by default | explain; nothing stored | autoAdapt correction |
| 8 | Approval | `onboarded`, first `PlanVersion` | Plan | Home, Plan, Train | exists | same | — |

## Cross-product behaviour
| Product | Receives from onboarding | Rule |
|---|---|---|
| **Home** | today's session, next action from Coach, recovery information if Health is connected | does not copy the Plan schedule or Progress; "no plan" state needed for unsupported-only athletes [new] |
| **Plan** | the approved first plan, goals, availability | owns them afterwards; every change previewed and approved |
| **Train** | selected activities → which entries the Training Hub v1.4 offers; cycling uses supported ride metrics; strength uses sets, reps, load | no native running or swimming recording is assumed; recovery timer/log only when built |
| **Progress** | which disciplines to show | endurance and strength evidence stay separate and labelled; rest information is context only, never performance evidence; Athlete Evolution follows its own approved framework and ignores declared experience |
| **Coach** | goals, availability, equipment, exclusions, flexibility | may **recommend** and **explain** at any time; must **request approval** for any change to load, volume, frequency or days; may **act without asking** only for protective reductions already authorised by the athlete's setting; never uses unsupported or unvalidated data |
| **Profile** | every answer, one home each (table above) | no duplicate value or editor; six sections unchanged |
| **Devices** | connection choices | live state never stored as profile; removing a device keeps history |
