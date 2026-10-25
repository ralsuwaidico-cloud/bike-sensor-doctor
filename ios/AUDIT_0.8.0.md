# iOS audit before 0.8.0 (25 Oct 2026) — what is complete, partial, broken or missing

Read against every earlier requirement; nothing marked complete was rebuilt. "Device" = confirmed by Rashed on hardware.

| Requirement | State before 0.8.0 | Evidence | 0.8.0 action |
|---|---|---|---|
| Five tabs Home / Plan / Ride / Progress / Profile, raised centre button | complete (0.4.0–0.7.0) | smoke tests tap all five | centre button made adaptive (Ride now / Train now…), design kept |
| Connections dashboard, colour rules, per-row details | complete (0.4.0); device: Rashed used it on build 24+ | RulesTests | board row gains "pairing lost" red + stage-aware subtitle |
| Background reconnect (state restoration + pending connect) | **partial**: worked, but "Connecting…" could sit forever and a stale pairing looped silently | Rashed: "Link: Connecting…", "Peer removed pairing information" | stages, 20 s watchdog, failure reasons, Repair flow, no retry loop on key loss |
| Pairing recovery after a board data reset | **broken** (no way out except iOS Settings + guessing) | same report | Repair sheet + new-identity handling (firmware 0.7.0) + board id continuity |
| Two-stage onboarding, Apple Health connected only after authorization | complete (0.4.0) | smoke fresh-install test | untouched |
| Profile sync phone-authoritative, versions, ACK, retries, differences dialog | **partial**: worked, but no field validation (board dropped values silently before 0.7.0), no persisted "last synced" shown, success not distinguished from "connected" | ProfileSync.swift 0.4.0 | validation mirroring the board, pending/synced hh:mm/failed, persisted per board, retry buttons, hello handling |
| Device settings gated on supported_mask; Wi-Fi setup over the link | complete (0.4.0) — needs firmware 0.6.0+ on the board | LinkV12Tests vectors | untouched |
| Ride dashboard (Nokia Power-Focus port), coach engine, launch-safe geometry | complete (0.5.0/0.5.1) | CoachCoreTests, smoke tests | untouched |
| Plan: availability editor, budgets never exceeded, per-day assignments, timeline, weekly review | complete (0.7.0) | HybridV2Tests | untouched; strength cards now show routines |
| Hybrid phase 1 (modes, quick log, dual coach, Health import) | complete (0.6.0) | HybridTests | untouched |
| Strength templates connected to the calendar | **missing** (templates existed, calendar showed a generic circuit) | Rashed, build 36 | assignments, weekday defaults, routine-based session screen |
| Equipment owned / exercises excluded | missing | brief | EquipmentProfile + pages + coach filtering |
| Next-workout insight (evidence-based, Accept/Ignore/Undo) | missing | brief | InsightEngine + InsightCard (Home + session screen) |
| Workout mode with set logging, pause/resume, partial save | missing | brief | StrengthSessionView + Store.activeSession (persisted) |
| Templates created directly, three separate data types | **partial** (creation went through "log a session and save it") | brief | TemplateEditor; a template never counts as completed |
| Google / e-mail sign-in | blocked on Supabase + Google OAuth configuration (Rashed) | — | unchanged |
| Android foundation | skeleton only | — | unchanged |

Hardware-only (cannot be proven in the simulator): every Bluetooth stage and reason on the real iPhone + board, the
Repair flow with the board's new identity, background reconnect timing, LINK_DIAG and PROFILE hello from firmware
0.7.0, and the whole routines journey on the glass. These are `BUILD<run>-TEST.txt`.
