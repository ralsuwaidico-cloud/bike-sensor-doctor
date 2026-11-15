# Cyclift — shared contracts for integration (v0.1, draft)

Status: **Current Draft** · 15 Nov 2026 · preparation only. Nothing here is implemented outside E1; no UX or AI code exists on any branch. Source facts were read at commit `4e2e9dc1` and are marked [SOURCE].

Purpose: the parallel workstreams (navigation, onboarding and Profile, Training Hub, Plan/Home/Progress, Coach) must be able to build against the same six interfaces, so that integration is a merge and not a rewrite.

## C1 · Save result (owner: data layer · exists on `ios/e1-safety`, not yet verified)

- A workout save is **one write**. It answers true only when the record reached storage.
- A failed write leaves memory exactly as it was: no record, planned session not completed, nothing for Home, Plan, Progress or Coach to read. A retry is not a duplicate.
- States every recorder shows: recording → saving → **saved and confirmed** · **not saved** (retry available) · **uncertain** (kept, checked again). Today E1 has "saved" and "not saved"; "saving" and "uncertain" are not modelled yet.
- Consumers: Train (all recorders), Watch coordinator, Health import, Coach (runs only after a committed save).

## C2 · Storage file (owner: data layer)

- One file, schema 4. Changes are **additive only**; a field is never renamed or re-typed.
- Unknown top-level fields are carried through saves. A higher schema number opens read-only.
- Every new stored field declares: default when absent, which build introduced it, and what an older build does with it.
- New fields already requested by the designs (none exist today): main-sport flag, roster entries with support level, sport modality per planned session, theme, language, nullable ratings, Coach ledger.

## C3 · Named destinations (owner: app shell)

[SOURCE] Tabs are numbers today: Home 0, Plan 1, Ride 2, Progress 3, Profile 4. References found:

| File | Uses |
|---|---|
| `ContentView.swift` | lines 14, 40, 52–56, 88, 99, 135, 140, 155, 172, 270 (`tabPage`) |
| `HomeView.swift` | 16 (binding), 46, 59, 137, 164 |
| `StrengthLog.swift` | 417 (binding), 508 |
| `DesignSystem/CyLiquidDock` (selection binding), `DesignSystemGallery.swift` 11, 183 |

Contract: `enum Destination { home, plan, progress }` for the dock; `train` is the left control and is not a tab; `ride` and `profile` are **presented destinations** (pushed or full-screen), reachable by name from anywhere. No view keeps a tab number.

[SOURCE] Ride start is reached from four call sites plus device adoption: `RideView.swift` 271, `PlanView.swift` 436, `BikeComputerApp.swift` 50 (Apple Watch), `Watch/CyWatchCoordinator.swift` 150, and adoption of a ride begun on the device inside the recorder's tick. Three of them pass `locationAuthorized: true` as a constant. Contract: one function "may a ride start, and if not why" (E1-F5), called by all; removing the Ride tab changes none of them.

Rules carried from Training Hub v1.4: one active session; the Train control opens it from any tab; a ride must be paused before it can be finished; cycling minimise stays blocked.

## C4 · Athlete record (owner: Profile for identity and devices; Plan for goals and week)

One editor per field, opened from onboarding and from Profile. [SOURCE] today `sports`, height and gender are stored and then zeroed for the planner (`Rc3Engine.swift` 387–390), so the roster has no consumer yet. Contract: the roster is persisted once with a support level per activity; Plan schedules only supported modalities; Train offers only real recorders; changing a profile value never rewrites a recorded session.

## C5 · Coach proposal and decision record (owner: Coach)

`Proposal { id, target session or week, change (typed), from, to, evidence references, origin: fact | rule | model, created }` → `Policy decision { automatic | needs approval | refused, policy id and version, reason }` → validator → one atomic commit of plan + `Decision { outcome: applied | approved | rejected | undone | not saved, when, reversal }`.

- Until the policy engine is validated, **every increase is "needs approval"** (E1 interim hold, owner decision 15 Nov). The contract already has the place where small weight and repetition steps become automatic; the hold is a setting of the policy, not a change of architecture.
- A rejected proposal is remembered for the same evidence and does not return.
- [SOURCE] today two engines can decide an increase (adaptive coach; planner rebuild). Under the hold neither applies one. Under this contract only the policy decision does.

## C6 · Post-session review (owner: Train)

Three independent, optional ratings — intensity, performance, effort — each `Int?`; nothing pre-selected; "not answered" is stored as absent, never as a number. The session is saved before the review and independently of it. [SOURCE] today the form starts at performance 7 / effort 6 and saves them as answers (`AdaptiveViews.swift` 18–19); stored 7/6 pairs cannot be told apart from real answers.

## Shared components identified (build once)

| Component | Used by |
|---|---|
| Design tokens with a theme parameter; string catalogue | Every new view |
| Preview → approve → Undo sheet | Plan, Profile (plan-affecting edits), Coach |
| Session card with the six truthful states | Home, Plan, Train panel |
| Source/sensor state label (receiving, not verified, lost) | Onboarding 5, Profile, recorders |
| Save-state footer | Every recorder, review |
| "Declared by you" / "Measured" pair | Onboarding 6–7, Progress, Profile |

## Readiness of each workstream

| Workstream | Ready to build against | Waits for |
|---|---|---|
| Foundation and navigation | C3, approved Navigation v1.2 rev 1.1 | E1 merged before `ContentView` is edited; placeholder Train mark approval |
| Onboarding and Profile | C2, C4; Page 2 v3.4 | Visual approval of pages 1, 3–7 and Profile; primary-sport decision |
| Training Hub | C1, C6; Training Hub v1.4 | E1 save result verified; "saving" and "uncertain" states |
| Plan, Home, Progress | C3, C5 | Plan integration design; Home decisions |
| Coach foundation | C5 | Thresholds and allowlist only for enforcement; shadow mode needs neither |
