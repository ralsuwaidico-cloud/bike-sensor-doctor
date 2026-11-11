# Home v2 prototype — accessibility and small-device review

**Evidence level: simulator screenshots of the standalone UI Lab** (iOS 26.5 simulator; iPhone 17 and iPhone SE
3rd generation; text sizes Large and Accessibility Large). Nothing here was checked on a physical iPhone, and
VoiceOver was not listened to. It is a prototype review, not evidence about the production app.

## What was checked and how

| Check | Method | Result |
|---|---|---|
| Text contrast, all six themes | `tools/contrast_check.py` on the tokens: text on the three surfaces ≥ 4.5:1; category, status, ring and accent colours ≥ 3:1 as graphics and ≥ 4.5:1 where used as text; button label on accent ≥ 4.5:1 | 294 pairs, 0 failures, lowest text ratio 4.79:1 |
| Meaning without colour | Review of every status and category | Each status has an icon and a word; each category an icon and a label; missing data is a dashed ring with "?" and a reason |
| Touch targets | Code review: `CyHit.min` = 44 pt on buttons, chips, checklist rows, tab items, day cells (60 pt high) | Met by construction; chart status cells are 26 pt high (see findings) |
| Dynamic Type | Screenshots at Accessibility Large on both devices | Rings switch to a list, sport cards stack, text wraps; see findings |
| Small device | iPhone SE screenshots, both scroll positions, new-user state | Header, circles, strip and the top of the sport cards fit on the first screen; nothing truncated at the default size |
| Spoken descriptions | Code review of accessibility labels / values | Rings: label + value (percentage and count, or the status word, or the missing reason). Day cells: weekday, date, "today", day summary. Chart: one spoken summary per series plus a per-day control for each status cell. Cards: combined label. **Not yet heard with VoiceOver.** |

## Findings from the first prototype build

| # | Finding | Where | Severity | Status |
|---|---|---|---|---|
| 1 | Seventh day label on the chart axis was clipped ("…" instead of "Sun") | Trends chart, all themes | Medium | Fixed in the second build (axis padding) — to be confirmed in its screenshots |
| 2 | Scrolled content showed through under the status bar | Home, gallery | Medium | Fixed in the second build (background behind the status bar) — to be confirmed |
| 3 | Tab-bar labels grew with accessibility text and wrapped ("Train now" on two lines) | Tab bar at Accessibility Large | Medium | Fixed in the second build: labels stop growing at the largest standard size, as the system tab bar does. A long-press large-content viewer is still to add |
| 4 | Date line and "SAMPLE DATA" tag wrapped awkwardly at accessibility sizes | Header | Low | Fixed in the second build (tag moves to its own line); the tag is prototype-only anyway |
| 5 | Review sheet opened at half height and cut off the Approve button | Review sheet | Medium | Fixed in the second build (opens full height) |
| 6 | Sample chart showed 100 % while the ring showed 80 % | Sample data | Low | Fixed (sample data only) |
| 7 | At Accessibility Large the header, circles list and strip fill the first screen; the sport cards need a scroll | Home on both devices | Expected | Open for the owner's view: acceptable, or should the greeting be capped at one line at these sizes? |
| 8 | Chart status cells are 26 pt high — below the 44 pt target, though each is full column width and the same day can be chosen on the chart | Trends chart | Low | Open: raise the cells to 44 pt (taller card) or keep them compact |
| 9 | Chart axis labels crowd at Accessibility Large ("MonTue WedThu") | Trends chart | Low | Open: switch to single letters at accessibility sizes |
| 10 | Sport cards are tall at the default size (sparkline plus caption) | Endurance / Strength Load | Design | Open for the owner's review: keep the sparkline on Home, or move it to the detail sheet for a shorter Home |
| 11 | High Contrast is one dark variant; there is no light high-contrast variant | Theme | Design | Open: is a light variant wanted? |
| 12 | Load Balance and Recovery rings look alike when both are "good" (full ring, tick) — told apart by colour, title and word | Circles | Design | Open for the owner's review |

## Not covered (needs a real device or a later step)

- VoiceOver reading order and wording on a physical iPhone.
- Reduce Motion, Bold Text, Increase Contrast and Smart Invert system settings.
- Right-to-left layout and languages other than English.
- Landscape (the prototype is portrait only) and iPad.
- One-handed reach and readability while exercising.
