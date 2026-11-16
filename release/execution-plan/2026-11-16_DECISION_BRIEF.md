# Cyclift — decisions for the owner (16 Nov 2026)

Status: **Recommendations. Nothing here is approved, built into the app, or active.** Each item names the existing
document that holds the detail, so this page stays short. Answer each with: approve / change / not yet.

## 1. Automatic small steps (load and repetitions)

Detail: `product/coach/design-review-v2/COACH_FUELING_DESIGN_REVIEW.md`, section E1.

| Rule | Recommendation |
|---|---|
| +1 repetition per set (P-REP-1) | Approve as drafted: only inside the programmed range; needs the last 2 comparable sessions within 21 days, every set completed, effort answered and 8 or lower both times; at most once per exercise per 7 days; at most 3 automatic steps per session |
| One weight step (P-LOAD-1) | Approve as drafted, **but start switched off** for the first beta: one smallest available step, never more than 10 % of the current load, only on exercise classes marked "auto", at most once per exercise per 14 days, never together with a repetition step |
| Everything else (sets, intervals, duration, holds, frequency, larger steps) | Stays approval-only, as you decided on 15 Nov |
| Pain | Only an explicit, current "no pain" permits a step (your decision of 16 Nov; built and tested in shadow mode). **Still needed from you: how old may a "no pain" answer be?** I recommend: it must come from the review of the same two sessions the step is based on |

Why reps before load: a repetition step is the smallest change and is easily undone; a weight step depends on knowing
the athlete's equipment increments, which the app does not always know.

## 2. Protective actions that may happen without asking

Detail: `product/coach/AUTOADAPT_CORRECTION_PROPOSAL.md`, section 5 (items P1–P13).

| Recommendation | Items |
|---|---|
| Automatic, always listed with a reason and Undo | P9 hold loads and reps (no increase); P13 ride caps and pauses after a health-check answer (already approved E1 behaviour); P12 the programmed deload week |
| Automatic **only after** it is shown working on a device, with Undo | P1 next hard ride one step easier on fatigue; P5 one repetition fewer after two sessions short of target at very high effort |
| Ask first | P2, P3, P4 shorter or reduced sessions; P8 lower weight; P10 restart below the last load after a long gap; P11 leaving out exercises that load a painful area |

Reason for asking on P11 in particular: it follows a pain report. The athlete should see what was removed and why,
and the wording should point to professional care for concerning pain rather than quietly reshaping the session.

## 3. Fueling guidance

Detail: design review section H (rules FU-0 onwards) and decisions M-11, M-12.

- Approve the scope: general, advice only, no numbers, no food record, shown after the session review.
- Frequency: at most one message a day; none after an easy session; none when a session was only "marked done".
- Off when: pain or illness is flagged, any health-check answer is "yes", age is under 18 or unknown.
- **Condition I recommend you keep:** wording reviewed by a qualified sports dietitian before any production use.
  Fueling can be left out of the first beta without blocking anything else.

## 4. AI deployment and privacy

Detail: design review section I; readiness package G2–G5.

- First beta: **no AI model.** Rules, the decision history and fixed questions work on every supported iPhone.
- Next: an isolated on-device prototype with synthetic athletes only. Nothing leaves the phone.
- Cloud: only after separate privacy, legal (UAE and other markets) and cost decisions.
- In every option the model may only propose; the policy check decides. Pain and health answers are not sent to any
  model without a field-by-field allowlist that you approve.
- Known limit: Apple's on-device model needs iOS 26 and an eligible iPhone; Cyclift supports iOS 17. Many athletes
  would have no assistant, so the no-AI experience must be complete on its own.

## 5. Theme and discipline colours

Decided 16 Nov: six themes kept; returning-athlete defaults; System option with an athlete-chosen light/dark pair.
Done in the isolated branch: nine prototype values corrected so every status and discipline colour reaches the
small-text contrast threshold. **Still for you:** approval of the colours themselves, which needs the six-theme
screen comparisons. Those are not produced yet.

Two points to settle on those screens (brand book §4.5): recovery and success are the same green in Arctic, Sandstone
and High Contrast; strength amber and warning amber are close in every theme.

## 6. Onboarding and Profile — what is actually outstanding

- Onboarding: page 2 (Athletic Roster v3.4) is selected. Pages 1 and 3–7 have no selected visual baseline.
- Onboarding page 5 wording about the Coach may only ship together with the working policy check (decision of 15 Nov).
- Profile v2.0: the six-section structure is approved; the visual treatment of each section is not.
- Recommendation: one comparison sheet per open page (two options each), not a new redesign.

## 7. Home and the quick menu

- Decided 16 Nov: the existing quick menu stays until a working replacement is approved.
- Recommendation: Home changes for the first beta are limited to the compact Coach card that opens the Coach page.
  Anything else from the Home v2.2 prototype waits for its own approval.
