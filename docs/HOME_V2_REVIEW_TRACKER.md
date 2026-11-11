# Home v2 — review tracker (prototype)

Page → Section → Card → Control → State → Expected behaviour → Actual prototype behaviour → Issue → Approval status.

**No row is approved.** Only the owner changes the last column. "Actual prototype behaviour" describes the
UI Lab build in the simulator; it is not evidence about the production app or a physical iPhone.

| Page | Section | Card | Control | State | Expected behaviour | Actual prototype behaviour | Issue | Approval status |
|---|---|---|---|---|---|---|---|---|
| Home v2 | 1 Header | Header | Date line | Normal | Today's date in small capitals | Sample date shown |  | Awaiting owner review |
| Home v2 | 1 Header | Header | Greeting | Normal | Greeting with the athlete's name, wraps to two lines at most | Sample greeting shown |  | Awaiting owner review |
| Home v2 | 1 Header | Header | Greeting | Loading | Placeholder line | Skeleton line shown |  | Awaiting owner review |
| Home v2 | 1 Header | Header | Avatar button | Normal | Opens Profile | Opens the Lab tab (prototype stand-in for Profile) |  | Awaiting owner review |
| Home v2 | 1 Header | Header | SAMPLE DATA tag | Prototype only | Marks all values as synthetic | Shown; to be removed at integration |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Consistency ring | Normal | Arc, percentage and 'n of m sessions' | Shown as specified (Established scenario) |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Consistency ring | Missing data | Dashed ring, 'Starts with your first session' | Shown as specified (New user scenario) |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Consistency ring | Loading | Track with spinner and 'Loading' | Shown (Loading scenario) |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Consistency ring | Tap | Opens detail: how it is worked out; what it does not tell you | Opens a sample detail sheet with Close |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Consistency ring | Large text | Rings become a list with full-width text | List layout at accessibility sizes |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Load Balance ring | Normal | Status word with icon, no number | Shown as specified (Established scenario) |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Load Balance ring | Missing data | Dashed ring, 'Needs 4 weeks of sessions' | Shown as specified (New user scenario) |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Load Balance ring | Loading | Track with spinner and 'Loading' | Shown (Loading scenario) |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Load Balance ring | Tap | Opens detail: how it is worked out; 'not a validated safe-training zone'; 'not recovery' | Opens a sample detail sheet with Close |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Load Balance ring | Large text | Rings become a list with full-width text | List layout at accessibility sizes |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Recovery ring | Normal | Status word with icon, no number | Shown as specified (Established scenario) |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Recovery ring | Missing data | Dashed ring, 'No readings' | Shown as specified (New user scenario) |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Recovery ring | Loading | Track with spinner and 'Loading' | Shown (Loading scenario) |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Recovery ring | Tap | Opens detail: how it is worked out; 'not medical advice' | Opens a sample detail sheet with Close |  | Awaiting owner review |
| Home v2 | 2 Circles | Circles card | Recovery ring | Large text | Rings become a list with full-width text | List layout at accessibility sizes |  | Awaiting owner review |
| Home v2 | 3 Getting Started | Getting Started card | Position | Essential step open | Directly below the circles, list expanded | Shown below the circles (New user scenario) |  | Awaiting owner review |
| Home v2 | 3 Getting Started | Getting Started card | Position | All essential steps done | At the bottom of Home, collapsed 'Setup complete' | Moves to the bottom when both essential steps are ticked |  | Awaiting owner review |
| Home v2 | 3 Getting Started | Getting Started card | Header row | Tap | Expands / collapses the list | Works locally |  | Awaiting owner review |
| Home v2 | 3 Getting Started | Getting Started card | Progress bar | Normal | Done ÷ total | Shown |  | Awaiting owner review |
| Home v2 | 3 Getting Started | Getting Started card | Step row | Tap | Opens that step's destination | Toggles done locally (prototype stand-in) |  | Awaiting owner review |
| Home v2 | 3 Getting Started | Getting Started card | Step row | Done | Green tick and strikethrough | Shown |  | Awaiting owner review |
| Home v2 | 3 Getting Started | Getting Started card | Step row | Optional | 'Optional' label | Shown |  | Awaiting owner review |
| Home v2 | 4 Seven-day strip | Strip card | Day cell | Normal | Weekday letter, sport icon(s), status icon | Shown for 7 days |  | Awaiting owner review |
| Home v2 | 4 Seven-day strip | Strip card | Day cell | Today | Outlined and tinted | Shown |  | Awaiting owner review |
| Home v2 | 4 Seven-day strip | Strip card | Day cell | Two sessions | Two stacked sport icons | Shown (Wednesday in the sample) |  | Awaiting owner review |
| Home v2 | 4 Seven-day strip | Strip card | Day cell | Rest | Moon icon | Shown |  | Awaiting owner review |
| Home v2 | 4 Seven-day strip | Strip card | Day cell | Tap | Opens the Day page | Opens a sample day sheet |  | Awaiting owner review |
| Home v2 | 4 Seven-day strip | Strip card | Strip | Empty | 'No plan for this week yet.' | Shown in the gallery |  | Awaiting owner review |
| Home v2 | 4 Seven-day strip | Strip card | Strip | Loading | Seven placeholder cells | Shown (Loading scenario) |  | Awaiting owner review |
| Home v2 | 5 Sport cards | Endurance card | Whole card | Normal | Time done, 'of planned', bar, distance, 8-week sparkline | Shown (Established scenario) |  | Awaiting owner review |
| Home v2 | 5 Sport cards | Endurance card | Whole card | Empty / insufficient data | 'No rides yet…' message | Shown (New user scenario) |  | Awaiting owner review |
| Home v2 | 5 Sport cards | Endurance card | Whole card | Loading | Placeholder blocks | Shown (Loading scenario) |  | Awaiting owner review |
| Home v2 | 5 Sport cards | Endurance card | Whole card | Tap | Opens Progress for that sport | Opens a sample sheet with weekly bars |  | Awaiting owner review |
| Home v2 | 5 Sport cards | Strength Load card | Whole card | Normal | 'n of m sessions completed', bar, volume, sparkline | Shown (Established scenario) |  | Awaiting owner review |
| Home v2 | 5 Sport cards | Strength Load card | Whole card | Empty / insufficient data | True zero count and 'Trend appears after two weeks…' | Shown (New user scenario) |  | Awaiting owner review |
| Home v2 | 5 Sport cards | Strength Load card | Whole card | Loading | Placeholder blocks | Shown (Loading scenario) |  | Awaiting owner review |
| Home v2 | 5 Sport cards | Strength Load card | Whole card | Tap | Opens Progress for that sport | Opens a sample sheet with weekly bars |  | Awaiting owner review |
| Home v2 | 5 Sport cards | Both cards | Layout | Large text | Cards stack vertically | Stacks at accessibility sizes |  | Awaiting owner review |
| Home v2 | 6 Coach | Coach row | Sentence | Normal | One sentence from the rules-based coach | Sample sentence shown, labelled rules-based |  | Awaiting owner review |
| Home v2 | 6 Coach | Coach row | Why? button | Tap | Opens the explanation | Opens a sample explanation sheet |  | Awaiting owner review |
| Home v2 | 6 Coach | Coach row | Review button | Proposal present | Opens review and approval | Opens the review sheet |  | Awaiting owner review |
| Home v2 | 6 Coach | Coach row | Not now button | Proposal present | Postpones without declining | Shows a sample toast |  | Awaiting owner review |
| Home v2 | 6 Coach | Coach row | Row | No suggestion | Explains what the coach is waiting for | Shown (New user scenario) |  | Awaiting owner review |
| Home v2 | 6 Coach | Coach row | Row | Loading | Placeholder lines | Shown (Loading scenario) |  | Awaiting owner review |
| Home v2 | 6 Coach | Review sheet | Approve | Tap | Applies the change | Closes with 'Sample only — nothing was changed.' |  | Awaiting owner review |
| Home v2 | 6 Coach | Review sheet | Not now | Tap | Postpones | Closes with a sample toast |  | Awaiting owner review |
| Home v2 | 6 Coach | Review sheet | Decline | Tap | Declines | Closes with a sample toast |  | Awaiting owner review |
| Home v2 | 6 Coach | Review sheet | Approve | Blocked | Disabled, with the reason shown | Shown in the gallery (Sheets) |  | Awaiting owner review |
| Home v2 | 7 Trends | Trends card | Series chips | Tap | Shows / hides a series; one always stays on | Works locally |  | Awaiting owner review |
| Home v2 | 7 Trends | Trends card | Consistency line | Normal | Percentage per day; missing days leave a gap | Shown; future days empty |  | Awaiting owner review |
| Home v2 | 7 Trends | Trends card | Load Balance row | Normal | One status cell per day, words not numbers | Shown |  | Awaiting owner review |
| Home v2 | 7 Trends | Trends card | Recovery row | Normal | One status cell per day, words not numbers | Shown |  | Awaiting owner review |
| Home v2 | 7 Trends | Trends card | Chart / day cell | Touch | Selects the day and shows a readout | Works locally |  | Awaiting owner review |
| Home v2 | 7 Trends | Trends card | Card | Empty | 'Trends appear once you have completed sessions…' | Shown (New user scenario) |  | Awaiting owner review |
| Home v2 | 7 Trends | Trends card | Card | Loading | Placeholder block | Shown (Loading scenario) |  | Awaiting owner review |
| Home v2 | 7 Trends | Trends card | Chart | VoiceOver | Spoken summary of each series | Summary text provided; not yet heard on a real iPhone | Real-device VoiceOver check outstanding | Awaiting owner review |
| Home v2 | Navigation | Tab bar | Home tab | Selected | Accent colour | Shown |  | Awaiting owner review |
| Home v2 | Navigation | Tab bar | Plan / Progress tabs | Tap | Open their screens | Show 'not prototyped yet' |  | Awaiting owner review |
| Home v2 | Navigation | Tab bar | Centre 'Train now' | Tap | Opens the Training Hub | Opens a placeholder sheet |  | Awaiting owner review |
| Home v2 | Navigation | Tab bar | Centre badge | Normal | Number of sessions today | Sample count shown |  | Awaiting owner review |
| Home v2 | Themes | Whole screen | Obsidian theme | Normal | All tokens applied; meanings unchanged; contrast ≥ 4.5:1 for text | Screenshot captured; contrast check passed for the token pairs |  | Awaiting owner review |
| Home v2 | Themes | Whole screen | Arctic theme | Normal | All tokens applied; meanings unchanged; contrast ≥ 4.5:1 for text | Screenshot captured; contrast check passed for the token pairs |  | Awaiting owner review |
| Home v2 | Themes | Whole screen | Ocean theme | Normal | All tokens applied; meanings unchanged; contrast ≥ 4.5:1 for text | Screenshot captured; contrast check passed for the token pairs |  | Awaiting owner review |
| Home v2 | Themes | Whole screen | Forest theme | Normal | All tokens applied; meanings unchanged; contrast ≥ 4.5:1 for text | Screenshot captured; contrast check passed for the token pairs |  | Awaiting owner review |
| Home v2 | Themes | Whole screen | Sandstone theme | Normal | All tokens applied; meanings unchanged; contrast ≥ 4.5:1 for text | Screenshot captured; contrast check passed for the token pairs |  | Awaiting owner review |
| Home v2 | Themes | Whole screen | High Contrast theme | Normal | All tokens applied; meanings unchanged; contrast ≥ 4.5:1 for text | Screenshot captured; contrast check passed for the token pairs |  | Awaiting owner review |
| Home v2 | Themes | Lab | Theme switch | Tap | Whole prototype updates immediately | Works locally |  | Awaiting owner review |

Rows: 72
