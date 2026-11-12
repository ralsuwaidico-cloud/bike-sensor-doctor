#!/usr/bin/env python3
"""Generates docs/HOME_REVIEW_TRACKER.md and .csv for Home v2.2.
Approval status is always 'Awaiting owner review' — only the owner changes it.
The 'Interaction evidence' text is taken from the interaction-test results file (argument 1); a row that names a
test is only described as passed when that test passed on every simulator it ran on."""
import csv, pathlib, re, sys
P = "Home v2.2"
res = {}   # test number -> list of (device, passed)
dev = None
if len(sys.argv) > 1 and pathlib.Path(sys.argv[1]).exists():
    for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
        m = re.match(r"== (\w+) \((.*?)\)", line)
        if m: dev = m.group(2).replace("-", " "); continue
        m = re.match(r"\s+(passed|failed)\s+test(\d+)_", line)
        if m and dev: res.setdefault(int(m.group(2)), []).append((dev, m.group(1) == "passed"))
def ev(*tests):
    if not tests: return "Visual only (screenshot)"
    out = []
    for t in tests:
        r_ = res.get(t)
        if not r_: out.append(f"T{t:02d} not run")
        elif all(ok for _, ok in r_): out.append(f"T{t:02d} passed ({', '.join(d for d, _ in r_)} simulator)")
        else: out.append(f"T{t:02d} FAILED on " + ", ".join(d for d, ok in r_ if not ok))
    return "; ".join(out)
rows = []
def r(section, card, control, state, expected, actual, tests=(), issue=""):
    rows.append([P, section, card, control, state, expected, actual + " — " + ev(*tests), issue, "Awaiting owner review"])

r("1 Header","Header","Date · athlete type / name","Normal","Compact, one line each","Unchanged from v2.1")
r("1 Header","Header","Avatar","Tap","Opens Profile","Opens the mock profile sheet",(18,))
r("2 Indicators","Consistency","Ring","Normal","Unchanged concept and visual","Unchanged (75 %, 3 of 4 in the sample)")
r("2 Indicators","Consistency","Ring","Tap","Adherence detail","Opens the Consistency sheet",(1,))
r("2 Indicators","Training Mix","Rings","Normal","Outer = endurance, inner = strength, each completed ÷ planned","Unchanged double ring")
r("2 Indicators","Training Mix","Centre","Hybrid","Ratio of completed training time, e.g. 60:40; the word 'Mix' removed","'66:34' from 77 and 40 sample minutes; caption 'Ride : Lift time'",(2,))
r("2 Indicators","Training Mix","Centre","Cycling only","100:0","'100:0'",(3,))
r("2 Indicators","Training Mix","Centre","Strength only","0:100","'0:100'",(3,))
r("2 Indicators","Training Mix","Centre","No completed training","Unavailable state, not a made-up ratio","'—' and 'No training time yet'",(3,))
r("2 Indicators","Training Mix","Centre","Loading","No value","Empty centre",(22,))
r("2 Indicators","Training Mix","Indicator","Tap","Sheet explains ratio vs rings; shows planned distribution","Completed ratio, planned ratio, completed minutes, two explanations, per-discipline progress",(1,2))
r("2 Indicators","Training Mix","Formula","—","Minutes only; never kg, watts, distance or session load mixed","Formula stated in the sheet and in the code; recomputed independently by the test",(2,))
r("2 Indicators","Recovery","Glyph","Numerical (sample)","Heart and three arcs removed; percentage in the centre; clearly marked sample","Single ring with '68%'; caption 'Sample score'; spoken as sample data",(4,))
r("2 Indicators","Recovery","Glyph","Qualitative only","Status word, no percentage (production fallback)","Plain ring with a text icon, 'In your usual range'; no % anywhere",(5,))
r("2 Indicators","Recovery","Glyph","Partial data","Says partial, no percentage","Dashed ring, 'Partial data'",(6,))
r("2 Indicators","Recovery","Glyph","Missing","Says awaiting, no percentage","Dashed ring with a dash, 'Awaiting data'",(6,))
r("2 Indicators","Recovery","Sheet","Numerical (sample)","Readings, freshness, guidance, sample marking, not medical clearance","'68% · Sample score', SAMPLE SCORE tag, three readings, 'About the number', 'Not medical advice'",(4,))
r("2 Indicators","Recovery","Sheet","Partial / missing","Missing inputs listed; nothing estimated","'Missing today' lists exactly the readings without a value",(6,))
r("2 Indicators","All three","Row","Large text","Separate, readable, usable","Stack as rows; do not overlap; each opens its sheet",(21,))
r("3 Getting Started","Setup card","Position","Required step open","Below the indicators, above the schedule","Measured position between indicators and schedule",(20,))
r("3 Getting Started","Setup card","Next step","Tap (complete)","Card leaves the top","Card disappears; 'Setup complete' line appears below the key metrics",(20,))
r("3 Getting Started","Setup line","Position","Established athlete","Bottom of Home only","Below the last metric row",(20,))
r("4 Schedule","Schedule","Session mark","Completed","Clearly separate icon; no circle; no green tick","Coloured icon with a filled dot under it")
r("4 Schedule","Schedule","Session mark","Planned","Different without colour alone","Muted icon with a hollow dot")
r("4 Schedule","Schedule","Session mark","Missed","Different without colour alone","Muted icon with a cross")
r("4 Schedule","Schedule","Session mark","Rescheduled","Different without colour alone","Muted icon with an arrow")
r("4 Schedule","Schedule","Day cell","Two sessions","Two separate icons, no overlap, readable on the smallest iPhone","Two icons side by side with their own marks; both spoken with their state",(7,),"Owner to judge legibility on iPhone SE from the screenshot")
r("4 Schedule","Schedule","Day cell","Rest day","Subtle","Small moon; spoken 'Rest day'",(7,))
r("4 Schedule","Schedule","Day cell","Tap (each of 7 days)","Opens that day","Each day opens the sheet titled with its own date",(7,))
r("5 Sport cards","Endurance / Strength","Card","Normal","Near approval: no sparklines; duration, bar, one metric","Unchanged from v2.1")
r("5 Sport cards","Endurance / Strength","Card","Tap","Detail sheet","Opens the discipline sheet (launch option screenshots)")
r("6 Sleep","Sleep bar","Row","Normal","Readable: last night, 7-day average, target; each labelled","'7h 10m last night', bar, '7-day avg 7h 02m', 'Sample target 8h 00m'",(8,))
r("6 Sleep","Sleep bar","Row","No sleep source","Truthful empty state","'No sleep recorded'; sheet says 'No record'",(8,))
r("6 Sleep","Sleep sheet","Explanation","—","Distinguish last night / average / target / recommendation; no new algorithm","'Four different things' block; target source stated; no recommendation is shown")
r("7 Coach","Coach banner","Text","Suggestion","Observation → Recommendation → Action","Observation line, bold recommendation, then Review / Not now")
r("7 Coach","Coach banner","Why?","Tap","Explanation","Opens 'Why this suggestion?'",(9,))
r("7 Coach","Coach banner","Review","Tap","Review sheet with three outcomes","Opens the review sheet with Approve / Not now / Decline",(9,))
r("7 Coach","Coach banner","Not now","Tap","Postpone, not decline","'Postponed — still waiting'; Review stays",(9,))
r("7 Coach","Review sheet","Approve","Tap","Accepted; sheet closes","'Accepted' note; actions removed; sheet gone",(10,))
r("7 Coach","Review sheet","Decline","Tap","Declined","'Declined' note; actions removed",(10,))
r("7 Coach","Review sheet","Not now","Tap","Postponed","'Postponed' note; Review stays",(9,))
r("7 Coach","Coach banner","Label","Any","Truthfully rule-based","'rules-based' tag")
r("8 Trends","Graph","Chart type","Normal","Multi-series line graph with point markers (bar chart replaced)","Lines with a point per measurement")
r("8 Trends","Graph","View A","Training & Recovery","Load + recovery % (sample only) on separate labelled scales","Left scale 'Training load (RPE×min)', right scale 'Recovery (% · sample)'",(11,))
r("8 Trends","Graph","View B","Training activity","Endurance, strength, planned minutes","Three series on one minutes scale; planned dashed",(14,))
r("8 Trends","Graph","View C","Recovery trends","RHR, HRV, sleep with metric selection","One metric at a time, each in its own unit",(14,))
r("8 Trends","Graph","Day","Tap","Selects the day; exact date and values","Vertical guide, enlarged points, panel with date and each value",(11,))
r("8 Trends","Graph","Day","Drag (scrub)","Selection follows the finger","Selection follows a drag in both directions",(12,))
r("8 Trends","Graph","Page scroll","Vertical swipe over the graph","Page still scrolls","Page scrolls",(13,))
r("8 Trends","Graph","Missing day","Any view","Gap; no interpolation; says missing","Line breaks; panel says 'No data'",(11,15))
r("8 Trends","Graph","Series chips","Tap","Show / hide a series; last one stays","Hidden series leaves the graph and the panel; last visible series cannot be hidden",(14,))
r("8 Trends","Graph","Range","7 days / 4 weeks","Switches range; selection cleared","7 days = 7 points, 4 weeks = 28 points; selection cleared on switch",(15,))
r("8 Trends","Graph","Open day","Tap","Daily sheet for the selected date","Sheet titled with the date, listing that day's values",(11,))
r("8 Trends","Graph","Info","Tap","Methodology","'How Trends works' with views, scales, missing days, sample note, sources",(16,))
r("8 Trends","Graph","Empty","New athlete / no recovery source","Truthful empty state","Empty text instead of a graph",(16,))
r("8 Trends","Graph","Stress / strain score","—","None","None present")
r("9 Key metrics","Metric rows","Layout","Normal","Rows (approved direction), neutral direction markers","Rows with icon, name, value, unit, baseline, marker, chevron; grid removed")
r("9 Key metrics","Metric rows","Weekly load","Normal","Documented unit, no arbitrary points","'561 RPE×min' with '4-wk avg 1,291'",(17,))
r("9 Key metrics","Metric rows","Row","Tap (each of 6)","Metric detail","Each row opens the sheet with its own title",(17,))
r("9 Key metrics","Metric rows","Row","Missing","'No data', never zero","Shown in the no-recovery and new-athlete scenarios")
r("Navigation","Floating dock","Destinations","Tap","Switches destination","Home, Plan, Progress, Profile switch; Train now opens its sheet",(18,))
r("Navigation","Floating dock","Dock","End of page","Never covers the final rows","Last metric row and the final line end above the dock; last row can be tapped",(19,))
r("States","Whole screen","Loading","—","No default values","No ratio, no percentage, no graph, no coach actions",(22,))
for t in ["Obsidian","Arctic","Ocean","Forest","Sandstone","High Contrast"]:
    r("Themes","Whole screen",t,"Normal","Six themes only; meanings unchanged; selective gradients (flat in High Contrast)","Screenshots captured; token contrast check passed")
for s in ["Established hybrid","New athlete","Cycling only","Strength only","No planned sessions","No recovery data","Partial sensor data","No sleep source","Long name","Small iPhone","Large Dynamic Type"]:
    r("Scenarios","Whole screen",s,"—","Truthful, stable layout","Captured in the simulator")

out = pathlib.Path(__file__).resolve().parents[1] / "docs"
head = ["Page","Section","Card","Control","State","Expected behaviour","Actual prototype behaviour and evidence","Issue","Approval status"]
with open(out / "HOME_REVIEW_TRACKER.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(head); w.writerows(rows)
md = ["# Home v2.2 — review tracker (prototype)", "",
      "Page → Section → Card → Control → State → Expected behaviour → Actual prototype behaviour and evidence → Issue → Approval status.",
      "", "**No row is approved.** Only the owner changes the last column.",
      "\"T07 passed\" means interaction test 07 passed in the iOS Simulator on the UI Lab prototype with sample data.",
      "\"Visual only\" means the state was captured in a screenshot and nothing was tapped. Neither is evidence about",
      "the production app or a physical iPhone.", "",
      "| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
md += ["| " + " | ".join(c.replace("|", "/") for c in row) + " |" for row in rows]
md += ["", f"Rows: {len(rows)}"]
(out / "HOME_REVIEW_TRACKER.md").write_text("\n".join(md) + "\n")
print(len(rows), "rows")
