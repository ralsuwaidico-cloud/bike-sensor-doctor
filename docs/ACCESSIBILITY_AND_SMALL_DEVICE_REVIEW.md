# Home v2.2 — accessibility and small-device review (prototype)

Evidence level: iOS Simulator screenshots and simulator interaction tests only. **No physical iPhone, no VoiceOver
session.** This is a design review, not an accessibility sign-off.

## What was checked and how

| Topic | Check | Result |
|---|---|---|
| Text contrast | Script over the theme tokens: 6 themes, 294 pairs | 0 failures; lowest text ratio 4.79 |
| Colour alone | Review of every state | Session state uses a mark (dot / hollow dot / cross / arrow / moon). Recovery states differ by ring style and icon. Graph series have names in chips and in the value panel; "Planned" is dashed. Direction markers are neutral triangles |
| Spoken content | Read back by the tests through the accessibility tree | Mix: "66:34. Ride to lift time…"; Recovery: "68%. … sample"; two-session day speaks both sessions with their states; rest day speaks "Rest day"; graph days are individual elements; value panel is text |
| Tap targets | Tests tap each control | Indicators, seven day cells, sleep bar, coach actions, graph days, chips, range, metric rows, dock all respond in the simulator |
| Large text (AX-L) | Screenshots + test 21 | Indicators stack as rows and do not overlap; sheets open; graph scale titles stack as "Left: …" / "Right: …"; day letters replace day names under the graph |
| Small iPhone (SE 3rd gen) | Screenshots + the full test set | Layout holds; three view tabs fit; value panel fits. Tests: 20 of 22 passed in the last run (see the change log) |
| Graph without sight of colour | Review | Each visible series is named with its unit in the panel; missing values say "No data" |
| Motion | Review | No decorative animation was added |

## Known limits and risks

1. **Scrubbing is a drag gesture.** VoiceOver users use the per-day elements instead; this path was not tried with VoiceOver.
2. **28 day elements** in the 4-week view are narrow (about 10–12 pt each). Tapping an exact day is fiddly; dragging is the intended way. On a real phone this needs a hands-on check.
3. **View tabs at standard size on iPhone SE** use small text ("Training & Recovery") — readable in the screenshot, to be judged by the owner.
4. **Two-session day cells on iPhone SE**: two icons of about 13 pt side by side. Distinguishable in the screenshot; owner to judge.
5. **Dynamic Type beyond AX-L** (AX-XL to AX-XXXL) was not captured.
6. Reduce Motion, Bold Text, Increase Contrast and Differentiate Without Colour system settings were not exercised.
7. Interaction-test instability around sheets (see the change log) means "every sheet opens and closes every time" is not yet demonstrated.
