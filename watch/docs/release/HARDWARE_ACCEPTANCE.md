# Cyclift Watch — Stage 1.3 RC1 hardware acceptance (ONE guided session, proposed)

**Not approved. Nothing here runs until the owner approves the RC1 installation by name and fingerprint.**
Duration ≈ 60 min. Owner at the watch; Claude drives the PC tools (serial only after the install) and asks one thing at a
time. USB power only (no battery). Stop at the first failed check; nothing is improvised.

## Part 0 — install (needs its own approval)
`cy_update_s13.py`: `s13_pre` → `s13_write` → `s13_post` (ROLLBACK_AND_RECOVERY.md). Pass = boot banner
"Stage 1.3 RC1", whole-flash diff shows only the app1 span changed.

## Part 1 — checks (serial commands are read-only except T, which sets the clock chip as in C2)

| ID | Check | How | Pass when |
|---|---|---|---|
| H1 | Honest start | look at the face | "NOT SYNCED" chip; no Move / Load / "Next · Ride" values; time shown or `--:--` |
| H2 | Clock | `R`; if invalid: face shows `--:--` and **no date**; then `T<now>` | after `T`: time + weekday + date correct, in English and (after `l`) Arabic |
| H3 | Face swipes | swipe up / down / left / right from the face | Today / Quick Settings / Health / Activity; from each, the approved way back reaches the face |
| H4 | Widget carousel | from Health keep swiping left | Health → Coach → Activity → face; page dots move |
| H5 | Today and Week | `E` (demo data on), swipe up twice, Key 2 | Today shows the session and Start; Week shows the strip; Key 2 returns to Today |
| H6 | Simulated ride label | tap Start on Today | cockpit opens with the "Simulated ride" banner |
| H7 | Quick Settings | tap each row | brightness visibly changes (4 levels); theme cycles through 6; DND and Mode change; Mode Bike → Bike cockpit |
| H8 | Lock | Screen lock row; tap, swipe, press Key 1; then hold Key 1 for 1 s | taps / swipes / Key 1 do nothing while locked; the hold unlocks |
| H9 | Menu | Key 1; tap Today; Key 2; tap Settings | Today opens; Settings shows "Not in this release"; Key 2 goes back |
| H10 | Arabic, densities | `l`, `d`, `t` on Today, Quick Settings, a widget | nothing cut off or overlapping (owner's eye) |
| H11 | Memory | `M` at the face, after H3–H9, and after H12 | 8-bit internal heap free and minimum recorded; the minimum stays ≥ 80 KB (budget, see MEMORY_AND_PERFORMANCE.md) |
| H12 | 10-minute ride soak | `r`, wait 10 min with `u` every 30 s (automatic), then `h` | no restart; heap free constant; update frames p50 ≤ 80 ms; no frame over 400 ms |
| H13 | Restarts | 2 normal restarts, 2 USB reconnections | "Stage 1.3" banner each time; face shown; settings back to defaults (RAM only, by design) |
| H14 | End state | — | watch answers without reset; owner decides: keep RC1, or roll back to Stage 1.1 (`s13_rollback`, separate approval) |

Evidence: serial log on the owner's PC (private), owner answers recorded in `STAGE1_3_HW_RESULTS.md` (to be written after
the session). Result words: HARDWARE VERIFIED only for checks that passed here; everything else stays OFFLINE READY.
