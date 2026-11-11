#!/usr/bin/env python3
"""Generates docs/HOME_REVIEW_TRACKER.md and .csv for Home v2.1.
Approval status is always 'Awaiting owner review' — only the owner changes it."""
import csv, pathlib
P = "Home v2.1"
rows = []
def r(section, card, control, state, expected, actual, issue=""):
    rows.append([P, section, card, control, state, expected, actual, issue, "Awaiting owner review"])

r("1 Header","Header","Date · athlete type","Normal","One small line","Sample values shown")
r("1 Header","Header","Name","Normal","One line, not a large greeting","Sample name on one line")
r("1 Header","Header","Name","Long name","Stays on one line (scales, then truncates); wraps at accessibility sizes","Long-name scenario captured")
r("1 Header","Header","Avatar","Tap","Opens Profile","Opens a mock profile sheet")
r("2 Indicators","Consistency","Ring","Normal","Arc = completed ÷ sessions due; percentage inside; 'n of m sessions'","Shown (75 %, 3 of 4 in the sample)")
r("2 Indicators","Consistency","Ring","No sessions due","Dashed ring and a reason; never 0 %","Shown (new athlete, no plan)")
r("2 Indicators","Consistency","Ring","Tap","Weekly adherence detail","Sheet with counts and the week day by day; rest days listed as rest")
r("2 Indicators","Training Mix","Outer ring","Normal","Endurance completed vs planned, endurance colour","Shown")
r("2 Indicators","Training Mix","Inner ring","Normal","Strength completed vs planned, strength colour","Shown")
r("2 Indicators","Training Mix","Either ring","Discipline not planned","Inactive ring, not a failure","Dashed inactive track; caption says 'no … planned'")
r("2 Indicators","Training Mix","Centre","Normal","Simple 'Mix' label, no numbers","Shown")
r("2 Indicators","Training Mix","Indicator","Tap","Endurance / strength breakdown with explanations","Sheet with each discipline, its own bar and percentage, and what it does not show")
r("2 Indicators","Recovery","Glyph","Readings available","No full progress ring, no green tick, no percentage","Three arcs for available readings, heart icon, word")
r("2 Indicators","Recovery","Glyph","Partial data","Says partial","Dashed arcs for missing readings, 'Partial data'")
r("2 Indicators","Recovery","Glyph","Awaiting data","Says awaiting","Dashed arcs, hourglass, 'Awaiting data'")
r("2 Indicators","Recovery","Glyph","Concern","Warning icon and word; no medical-clearance wording","Shown in the gallery (sample wording)")
r("2 Indicators","Recovery","Indicator","Tap","Recovery details","Sheet with each reading, guidance, source and freshness")
r("2 Indicators","All three","Row","Loading","Stable layout, no default values","Tracks with spinners, 'Loading'")
r("2 Indicators","All three","Row","Large text","Readable list layout","Stacks as rows at accessibility sizes")
r("3 Getting Started","Setup card","Position","Required step open","Directly below the indicators, compact","Shown (new athlete)")
r("3 Getting Started","Setup card","Next required step","Tap","Opens that step","Marks it done locally (stand-in)")
r("3 Getting Started","Setup card","All steps","Tap","Shows every step with Required / Optional tags","Expands in place")
r("3 Getting Started","Setup line","Position","Required steps done","Minimal line at the bottom","'Setup complete · n optional left', expandable")
r("3 Getting Started","Setup","Optional steps","Not done","Do not block completion","Completion depends on required steps only")
r("4 Schedule","Schedule","Day cell","Completed session","Coloured, filled icon; no tick underneath","Filled disc in the discipline colour")
r("4 Schedule","Schedule","Day cell","Planned session","Muted / outlined icon","Thin outline, muted icon")
r("4 Schedule","Schedule","Day cell","Missed session","Clearly different, not colour alone","Dashed outline with a slash")
r("4 Schedule","Schedule","Day cell","Rescheduled session","Clearly different","Outline with an arrow")
r("4 Schedule","Schedule","Day cell","Rest day","Subtle rest symbol","Small moon")
r("4 Schedule","Schedule","Day cell","Two sessions","Both icons without crowding","Two marks side by side")
r("4 Schedule","Schedule","Day cell","Today","Easy to identify","Tinted cell, bold accent letter")
r("4 Schedule","Schedule","Day cell","Tap","Opens the day sheet","Day sheet with sessions and states")
r("4 Schedule","Schedule","Strip","Nothing planned","Truthful empty state","'No sessions planned this week'")
for c, n in [("Endurance card","duration done / planned, thin bar, distance"),("Strength card","sessions done / planned, thin bar, weight lifted; titled 'Strength'")]:
    r("5 Sport cards",c,"Card","Normal",f"Compact: {n}; no sparkline or caption","Shown")
    r("5 Sport cards",c,"Card","Missing / not planned","Truthful text, same height","'Not in your plan' / 'No … yet · n planned'")
    r("5 Sport cards",c,"Card","Loading","Skeleton","Shown")
    r("5 Sport cards",c,"Card","Tap","Detail sheet (history moved here)","Sheet with totals and 8-week history")
r("6 Sleep","Sleep bar","Row","Normal","Last night, thin bar, 7-day average, target, tap affordance","Shown; bar = last night ÷ target")
r("6 Sleep","Sleep bar","Row","No data","Truthful empty state","'No sleep recorded', empty bar, 'No target set'")
r("6 Sleep","Sleep bar","Row","Tap","Sleep detail","Sheet: last night, average, target and its source, recent nights, guidance, data source")
r("6 Sleep","Sleep bar","Target","Normal","Not fabricated; source stated","Labelled 'sample target for the prototype'")
r("7 Coach","Coach banner","Review","Decision pending","Primary action","Filled button; opens the review sheet")
r("7 Coach","Coach banner","Not now","Decision pending","Postpones; not a rejection","Marks 'Postponed — still waiting'; Review remains")
r("7 Coach","Coach banner","Why?","Any","Small explanation action","Opens the explanation sheet")
r("7 Coach","Review sheet","Approve","Tap","Accept","Banner shows 'Accepted'; actions removed")
r("7 Coach","Review sheet","Decline","Tap","Reject","Banner shows 'Declined'; actions removed")
r("7 Coach","Review sheet","Not now","Tap","Postpone","Banner shows 'Postponed'")
r("7 Coach","Coach banner","Label","Any","Truthfully rules-based","'rules-based' tag; explanation says no generative model")
r("7 Coach","Coach banner","Banner","No suggestion / new athlete","Meaningful text","Shown")
r("8 Trends","Trends","Chart","Normal","One coherent chart, 7-day default, one labelled unit","Stacked training minutes; planned as a faint bar; legend with unit")
r("8 Trends","Trends","Status rows","—","Removed","Removed (no Load Balance / Recovery rows)")
r("8 Trends","Trends","Chart","Touch a day","Highlight and daily values","Highlight band, bold label, tooltip with that day's rows")
r("8 Trends","Trends","Tooltip","Open day","Daily metrics","Sheet listing only what the sample holds")
r("8 Trends","Trends","Range control","Tap","7 days / 4 weeks","Switches the sample dataset")
r("8 Trends","Trends","Info","Tap","Methodology off the chart","'How Trends works' sheet")
r("8 Trends","Trends","Chart","Missing data","Empty, not zero","Empty column; tooltip 'No data'")
r("8 Trends","Trends","Chart","Large text","Abbreviated day labels, full spoken labels","Single letters; full names in the spoken summary")
r("8 Trends","Trends","Chart","VoiceOver","Accessible summary and day stepping","Summary and adjustable action provided; not yet heard on a real iPhone","Real-device VoiceOver check outstanding")
r("9 Key metrics","Metrics grid","Tile","Normal","Icon, name, value, unit, short comparison","Shown, two columns")
r("9 Key metrics","Metrics grid","Tile","Missing","Truthful empty state, not zero","'—' and 'No data'")
r("9 Key metrics","Metrics grid","Tile","Tap","Metric detail","Sheet with value, history, explanation, source")
r("9 Key metrics","Metrics grid","Selection","By athlete","Most useful metrics for sports and data","Sample sets differ by scenario; the selection rule itself is integration work","Rule to be defined at integration")
r("9 Key metrics","Metrics grid","Sleep","—","Not duplicated from the Sleep bar","No sleep tile")
r("Navigation","Floating dock","Destinations","Tap","Sliding highlight, mock destinations","Works locally")
r("Navigation","Floating dock","Train now","Tap","Recognisable centre action","Opens a sample sheet with today's sessions")
r("Navigation","Floating dock","Dock","Scroll to end","Nothing hidden underneath","Content ends above the dock")
for t in ["Obsidian","Arctic","Ocean","Forest","Sandstone","High Contrast"]:
    r("Themes","Whole screen",f"{t}","Normal","Tokens applied; meanings unchanged; gradients restrained (flat in High Contrast)","Screenshots captured; token contrast check passed")
for s in ["Established hybrid","New athlete","Loading","Cycling only","Strength only","No planned sessions","No Apple Health / partial sensors","Long name","Large text","Small iPhone"]:
    r("Scenarios","Whole screen",s,"—","Truthful, stable layout","Captured in the simulator")

out = pathlib.Path(__file__).resolve().parents[1] / "docs"
head = ["Page","Section","Card","Control","State","Expected behaviour","Actual prototype behaviour","Issue","Approval status"]
with open(out / "HOME_REVIEW_TRACKER.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(head); w.writerows(rows)
md = ["# Home v2.1 — review tracker (prototype)", "",
      "Page → Section → Card → Control → State → Expected behaviour → Actual prototype behaviour → Issue → Approval status.",
      "", "**No row is approved.** Only the owner changes the last column. This tracker replaces the Home v2 tracker",
      "(v2 was reviewed by the owner on 11–12 Nov and revised; its rows are in the branch history).",
      "\"Actual prototype behaviour\" describes the UI Lab build in the simulator; it is not evidence about the",
      "production app or a physical iPhone.", "",
      "| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
md += ["| " + " | ".join(c.replace("|", "/") for c in row) + " |" for row in rows]
md += ["", f"Rows: {len(rows)}"]
(out / "HOME_REVIEW_TRACKER.md").write_text("\n".join(md) + "\n")
print(len(rows), "rows")
