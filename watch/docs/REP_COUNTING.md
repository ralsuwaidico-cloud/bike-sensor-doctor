# Automatic rep counting — strategy, implementation state, validation plan (W0/W4)

**State today**: an experimental detector exists (`firmware/src/domain/rep_detector.hpp`) and passes host tests on
synthetic wrist motion (10 curls → 9 counted at confidence 0.98; 8 fast → 7; 6 slow → 6; two sets of 8 with a 45 s rest
→ 15; 20 s walking → 0; five knocks → 0). **No real wrist data has been recorded yet**; real accuracy is unknown.

Pipeline: BMA423 at 50 Hz (±4 g) → one-pole high-pass per axis (gravity / tilt) → signed projection on the running
principal movement axis (so orientation of the watch does not matter and the frequency is not doubled) → low-pass 3 Hz →
one full cycle = above +T, below −T, above +T, with an adaptive threshold (≥ 0.9 m/s², 35 % of recent peak), a minimum
half-cycle time (150 ms — knocks ring faster), a tempo floor (0.7 s) and a tempo band (±50 % of the running median) →
confidence from tempo regularity, amplitude consistency and rejected-cycle share. Known characteristic: the first rep
of a set is confirmed one cycle late → the UI always offers +1 / confirm.

Interaction (directive §6–7): large live counter · set finished → haptic + **Confirm / Correct / Undo** · manual count
always available · auto-count optional per exercise · corrections recorded as the athlete's word (not learned
automatically). Hybrid confirmation = auto count shown in grey until confirmed.

Exercises expected to work: biceps / hammer curl, shoulder press, lateral / front raise, upright row, one-arm row,
triceps extension, kettlebell swing. Expected unreliable (manual only until proven): squat, leg press, deadlift, bench
press (to be tested), planks / static holds, fixed-handle machines.

W4 validation dataset: ≥ 8 exercises × 3 tempos (1.2 / 2 / 4 s) × 3 wrist positions × 2 loads × 2 athletes if
possible, plus false movements (walking, drinking, adjusting the watch, re-racking, phone use). Ground truth typed on
the phone per set; raw 50 Hz samples kept on the watch (LittleFS) and exported over BLE. Acceptance per exercise:
≥ 90 % of sets within ±1 rep → auto-count enabled; otherwise manual-only with the reason shown.

External Polar sensors: standard BLE HR profile gives HR + RR only; raw accelerometer exists only through Polar's
proprietary PMD service (Verity Sense / OH1 / H10) — investigation item in W4, no dependency.
