# Canonical athlete model, sport-capability matrix and migration proposal

**Version:** 0.1 · 15 Nov 2026 · **Status:** Current Draft — PROPOSAL for owner review · **nothing implemented; no storage changed**
Labels: **[FACT]** read in the app · **[DESIGN]** proposed here · **[FUTURE]** not supported, not promised.

## 1. Principles
One stored value per fact; onboarding and Profile are two views of it [FACT today for the fields onboarding asks]. No second copy for Profile. Stored names and enum raw values are not renamed. Everything is additive. Unknown stays unknown.

## 2. The model — seven groups
| Group | Contents | Where it lives | Notes |
|---|---|---|---|
| **Personal identity** | name; date of birth; height; weight (+ source, date); units | profile; `settings.units` | [FACT] all fields exist. [DESIGN] one accessor for age over `dateOfBirth` / `birthYear` / `age` |
| **Athletic participation** | selected activities; primary activities; classification; experience per discipline; hybrid balance | profile (`sports`, `trainingMode`, `level`, `priority`), strength prefs (`experience`) | [DESIGN] `primaryActivities` is new and optional. Classification stays `cycling / strength / hybrid` in storage, shown as Endurance / Strength / Hybrid. **Recording capability is not stored** — it is a property of the app version (§3) |
| **Goals** | goals; main goal; per-sport effective goal | profile (`goals`, `primaryGoal`, derived `goal`), strength prefs (`goal`) | [FACT] one effective goal per sport. [DESIGN] "secondary goals" = the stored extra picks, stated as not yet shaping the plan. Sport-specific targets and goal compatibility rules: [FUTURE] |
| **Training availability** | days; minutes per session; two-a-day; equipment; restrictions; supersets; split; recovery preference | availability, equipment, strength prefs, profile | [FACT]. Owned by Plan for schedule; by Profile › Training Setup for equipment and preferences |
| **Performance configuration** | resting / max / threshold HR; zone method; FTP + source + date + verified flags; cadence; wheel | profile + provenance | [FACT]. Every value carries one of: measured · entered · estimated · unknown |
| **Connections** | Apple Health switches; Apple Watch; BikeComputer (Waveshare); Bluetooth sensors; experimental (Cyclift Watch link, off by default); future | settings + live device state | [FACT]. Live state is never stored as profile data |
| **Plan state** | Draft · Approved · Updated · Paused · Needs review | **derived, not stored** | [DESIGN] Draft = setup not approved (`onboarded == false`); Approved = first `PlanVersion`; Updated = a later version exists; Paused = `trainingPause` set; Needs review = a pending confirmation exists (today: `confirmSessionLength`, `confirmStrengthLevel`; proposed: activities need confirming after migration) |

**Kept separate [DESIGN, required by the owner]:** self-reported experience (above) is never written by Progress. Progress's evidence-based Athlete Evolution is never overwritten by a Profile edit. Neither reads the other's field as its own.

## 3. Sport-capability matrix
Capability belongs to the app build, not to the athlete. [FACT] as read at `4e2e9dc`; nothing was run.
| Activity | Stored today | Record in Cyclift | Plan | Import (verified) | Log by hand | Status shown |
|---|---|---|---|---|---|---|
| Road cycling | yes | yes — ride recorder | yes | Apple Health cycling workouts | — | Recordable |
| Indoor cycling | yes | yes — same ride recorder; **no indoor-specific mode found** | as cycling | as above | — | Recordable |
| Mountain bike | yes | yes — same recorder | as cycling | as above | — | Recordable |
| Commuting | yes | yes — same recorder | as cycling | as above | — | Recordable |
| Strength training | yes | yes — strength session and quick log | yes | Apple Health strength workouts | quick log | Recordable |
| Running | yes | **no** | no | **not verified** | no | Future only |
| Swimming | yes | **no** | no | not verified | no | Future only |
| Walking | **no — new entry** | no | no | not verified | no | Future only |
| Other | yes | no | no | no | no | Future only |
"Importable" and "Manually loggable" exist as statuses in the model but no activity is in either today. Health workouts Cyclift writes are cycling type only.

## 4. Migration and backwards compatibility — PROPOSAL
| Topic | Proposal |
|---|---|
| File format | Same `store.json`. Additive optional fields only, read with a default when absent (the pattern the file already uses) |
| Classification | `trainingMode` raw values unchanged. "Endurance" is a display label for `cycling` |
| Selected activities | Keep `sports`. Add `walking` to the list. **Do not rewrite silently.** Existing athletes keep what is stored; because the default is road cycling for everyone, a strength-only athlete whose list is still the untouched default is shown one "Confirm your activities" prompt (plan state: Needs review) |
| Unknown future activities | Reading must tolerate values this build does not know (keep and ignore) so a later build's data never breaks an older one. **Needs engineering confirmation** of how the array is decoded today |
| Primary activities | New optional list; absent = not stated |
| Onboarding position | Stored 101–105 (five stages) and legacy 1–9. Six screens need a new range (proposed 201–206) with a mapping: A→1 or 2 (2 if a type is already chosen), B→3, C→4, D→5, E→6 |
| Partial onboarding | Answers already saved stay; the athlete resumes at the mapped screen; nothing is asked twice |
| Existing approved plans | Untouched. Migration never regenerates a plan. New questions (height, units, activities) default to "not stated" |
| Missing optional values | Stay empty; never estimated to fill a screen |
| Historical records | Never rewritten. Weight, FTP and zones in past sessions keep the values recorded at the time |
| Existing Profile edits | Preserved — same fields |
| Device settings | No protocol or firmware change. Phone-side duplicates (units, HR source) unchanged in this proposal |
| Duplicate Health imports | Existing rules unchanged; adding activities must not widen import types without its own review |
| Restart / offline | All local; no network dependence; no account |
| Rollback | Because changes are additive, an older build ignores new fields — **to be proven by a test before any release** |

## 5. Tests to specify before any code (none exist yet for these)
Migration: old five-stage file → opens at the mapped screen; legacy 1–9 file; file with unknown activity value; strength-only athlete with default `sports` → prompt, no rewrite; approved plan byte-identical after migration. Read/write: every field edited in onboarding reads back identically in Profile and the reverse; no second copy appears in the file. Plan impact: a plan-affecting edit never applies without approval; decline leaves plan and inputs unchanged; undo restores exactly or is refused with a reason. Preservation: past sessions unchanged after weight, FTP, zone, equipment and activity edits; device removal leaves history. Incomplete onboarding: kill and relaunch at each screen; no active plan before approval. Existing tests must be updated, never weakened.
