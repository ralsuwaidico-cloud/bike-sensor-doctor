# Decision — Screen 1, Onboarding Welcome: canonical design (approved and locked)

**Date:** 20 Nov 2026, 17:01 (Dubai) · **Decided by:** owner · **Status:** **Visually approved and locked.** Not to be modified again without the owner's approval.

Part of the controlled screen-by-screen design review started 20 Nov 2026 (previous vs current, functional-preservation table, owner decides; no independent redesign of existing or approved screens).

## The canonical screen

1. **Hero:** the black-hole artwork, upper-middle of the screen. It is a still image produced by the drawing routine of the approved Progress design sheets (baseline form; one image per theme). Static.
2. **Headline:** "Your evolution starts here."
3. **Supporting text:** "Your goals. Your training. A better you, every day."
4. **Circular control:** label "Hold to begin", helper "Hold for 3 seconds". Press and hold for three seconds; a ring fills; releasing early resets it; a tap does nothing.
5. **Haptics:** light on hold start, success on completion.
6. **Transition:** the welcome screen fades out with a slight scale and blur, then About you appears.
7. **Accessibility:** VoiceOver / Switch Control activation starts onboarding without the sustained hold.
8. **Removed:** Cyclift icon, app name, the three-mark legend, the "Seven short pages…" paragraph, the "About two minutes…" line.
9. **Function preserved:** completing the hold does what "Get started" did — continue without an account, open page 1.

Lab controls (badge, Theme, Scenario, Restore) are not part of this screen and do not appear in the main app.

## State of evidence (development branch `ios/lab`; nothing uploaded)

| Stage | State |
|---|---|
| Approved (visual) | Yes — owner, 20 Nov 2026 |
| Implemented | Yes — commits `08b4bfbf`, `7da39754`, wording `58cec7b5` |
| Simulator, layout/interaction (earlier wording) | Fast check 23, run 44729422873, iPhone 15 Pro: tap and early release do nothing; ring resets; a drifting finger still completes; About you opens; seven pages to an approved plan |
| Redesigned main app (earlier wording) | iOS run 307 (44733033144): 7 of 7, no Lab strip on Welcome |
| Simulator, final wording | Fast check 24 requested on `c67e1883` — result to be added |
| Physical device | Not done: VoiceOver / Switch Control, haptics and the dissolve need a real iPhone |
| Other themes / largest text with the image | Not captured |
