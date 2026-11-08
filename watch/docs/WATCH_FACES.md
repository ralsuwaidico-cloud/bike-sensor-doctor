# Watch faces and complications (W0 concepts)

Three original faces for the round 240 × 240 display, each in the three theme families × dark / light. Rendered
concepts: `docs/watch-faces.html` (also published as the "Cyclift Watch Faces" page). Grading colours are fixed and
never theme tokens.

| Face | Idea | Large complications | Small complications |
|---|---|---|---|
| **Orbit** | the clock sits in the centre of two arcs: training load for the week (theme accent) and recovery (graded colour, with text); complications at N / E / S / W | time · next session | sleep (with "PHONE 06:10" source + time), battery, steps |
| **Chrono** | analog hands over a tick ring with three small dials (next session, weekly load, recovery) and the digital time under the hands | time (hands) | next, load, recovery, status line (date · battery · link) |
| **Pulse** | minimalist digital time with one contextual coaching line (graded dot + text) and a thin status bar | time · coach line | next session, battery, steps |

Complication registry (directive §4): time & date · steps (BMA423) · battery · next workout · daily training
progress · heart rate (external source only) · recovery summary · sleep duration · HRV · weather (when synced) ·
cycling activity · strength activity · notifications. **Rule**: a complication renders a value only with a valid
source; cached values show the source and age ("PHONE 06:10", "2 h ago"); a stale value (> 24 h) is greyed with a
clock icon; an unavailable one shows "—", never a number.

Adaptive hierarchy (directive §3C): morning → sleep + today's session large; during an activity the face is replaced
by the live view; 2 h after an activity → recovery + results card; evening → tomorrow's plan + bedtime. Only the
emphasis changes; the layout never moves, so the face stays calm.

Micro-interactions (§3D): arc fill animates once on wake (≤ 400 ms), a haptic tick on gesture completion, no looping
animation (battery; the iPhone learned this with run 154's dock glow).


## v2 refinements (owner directive 8 Nov 16:07 §7)

* **Orbit** — two arcs with tracks (load = accent, recovery = grade colour), 54 px clock, date + battery on one line, next activity in 14 px, ONE legend line naming the arcs (LOAD 65 % · RECOVERY GOOD). Status labels cut from four to one.
* **Chrono** — real hour / minute hands (32 / 46 px) inside a 54 px hub; dials at radius 78 so the hands never cover them; tick ring with hour marks; digital time + date between the lower dials.
* **Pulse** — one insight of ≤ 22 characters with a grade dot; the sentence lives behind a visible More.
* Native-size and six-appearance renders: `docs/gallery-v2.html`, `docs/native/face-*.png`.
