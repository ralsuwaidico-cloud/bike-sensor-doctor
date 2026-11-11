# Home v2.1 prototype — accessibility and small-device review

**Evidence level: simulator screenshots of the standalone UI Lab** — run 43108414885, commit `05e1202`, iOS 26.5
simulator, iPhone 17 and iPhone SE (3rd generation), text sizes Large and Accessibility Large. Nothing here was
checked on a physical iPhone, VoiceOver was not listened to, and no interaction was exercised by hand. It is a
prototype review, not evidence about the production app. (The Home v2 review it replaces is in the branch history.)

## What was checked and how

| Check | Method | Result |
|---|---|---|
| Text contrast, six themes | `tools/contrast_check.py` on the tokens | 294 pairs, 0 failures, lowest text ratio 4.79:1. v2.1 added no colour values; gradients are derived from checked tokens |
| Gradients | Review | Used on rings, bars, session marks and the coach surface only. Text never sits on a gradient fill (the Review button is a flat accent). The tail of a gradient bar is lighter than the checked colour by design. High Contrast is flat |
| Meaning without colour | Review of every state | Session state is a shape (filled disc, thin outline, dashed outline with slash, outline with arrow, moon). Recovery state is an icon and a word. Direction markers are triangles / dot |
| Touch targets | Code review | Indicators, day cells (50 pt high, full column), cards, Sleep row, coach actions, chart info, tooltip "Open day", metric rows (54 pt), dock items (64 pt): all at least 44 pt. Chart days are chosen by touching anywhere in the day's column |
| Dynamic Type | Screenshots at Accessibility Large, both devices | Indicators become rows with the value in text; sport cards stack; coach actions stack with Why? on its own row; chart legend stacks; day labels become single letters; metric rows wrap; dock labels stop growing |
| Small device | iPhone SE, four scroll positions + new athlete + long name | First screen: header, indicators, schedule, sport cards, Sleep bar and the top of the Coach card. Nothing truncated at the default size |
| Floating dock and content | Screenshots at the end of the scroll and mid-scroll | The last element ("Setup complete") ends above the dock; a soft fade sits behind the dock |
| Spoken descriptions | Code review of labels and values | Each indicator: title + full value (for Training Mix: both disciplines with done and planned, or "not planned"). Day cells: weekday, date, each session with its state. Chart: one summary plus an adjustable action to step through days. Metric rows: value, unit, comparison, direction in words. **Not yet heard with VoiceOver** |
| No fabricated scores | Review of every screen and sheet | No recovery percentage, readiness, stress, fitness-age or biological-age figure. Sleep target labelled as a sample. Missing values shown as "—" / "No data" / dashed marks |

## Findings

| # | Finding | Severity | Status |
|---|---|---|---|
| 1 | Large text: percentage and "Mix" were squeezed inside the small rings | Medium | Fixed and confirmed in run 43108414885 (value moved into the text) |
| 2 | Large text: coach header wrapped ("rules-based", "Why?") | Medium | Fixed and confirmed (tag stays on one line; Why? moves below the sentence) |
| 3 | Large text: chart legend truncated | Low | Fixed and confirmed (legend stacks) |
| 4 | Scrolled content showed sharply beneath the floating dock | Medium | Fixed and confirmed (fade) |
| 5 | Large text: the date / athlete-type line wraps to two lines and the SAMPLE tag sits beside it | Low | Open (the tag is prototype-only) |
| 6 | Large text: with Why? below the sentence, the coach card is tall and its actions fall below the first screen | Expected | Open for the owner's view |
| 7 | Two session marks in one day are 19 pt each; clear on iPhone 17, tight on iPhone SE | Low | Open for the owner's view |
| 8 | Full-length review images draw ring arcs from a different start angle and omit the dock | Review aid only | Documented; on-screen screenshots are correct |
| 9 | One blank capture on iPhone SE in the earlier run | Capture only | Retaken; not a product issue |

## Not covered (needs a real device or a later step)

- VoiceOver reading order and wording on a physical iPhone; the chart's adjustable action in practice.
- Tapping through each interaction by hand; animation feel of the dock highlight and Reduce Motion.
- Bold Text, Increase Contrast, Smart Invert; right-to-left layout; languages other than English.
- Landscape and iPad (the prototype is portrait only).
