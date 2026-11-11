#!/usr/bin/env python3
"""Generates docs/HOME_V2_REVIEW_TRACKER.md and .csv. Approval status is always 'Awaiting owner review' —
only the owner changes it."""
import csv, pathlib
P = "Home v2"
rows = []
def r(section, card, control, state, expected, actual, issue=""):
    rows.append([P, section, card, control, state, expected, actual, issue, "Awaiting owner review"])

r("1 Header","Header","Date line","Normal","Today's date in small capitals","Sample date shown")
r("1 Header","Header","Greeting","Normal","Greeting with the athlete's name, wraps to two lines at most","Sample greeting shown")
r("1 Header","Header","Greeting","Loading","Placeholder line","Skeleton line shown")
r("1 Header","Header","Avatar button","Normal","Opens Profile","Opens the Lab tab (prototype stand-in for Profile)")
r("1 Header","Header","SAMPLE DATA tag","Prototype only","Marks all values as synthetic","Shown; to be removed at integration")
for name, normal, missing, det in [
    ("Consistency","Arc, percentage and 'n of m sessions'","Dashed ring, 'Starts with your first session'","how it is worked out; what it does not tell you"),
    ("Load Balance","Status word with icon, no number","Dashed ring, 'Needs 4 weeks of sessions'","how it is worked out; 'not a validated safe-training zone'; 'not recovery'"),
    ("Recovery","Status word with icon, no number","Dashed ring, 'No readings'","how it is worked out; 'not medical advice'")]:
    r("2 Circles","Circles card",f"{name} ring","Normal",normal,"Shown as specified (Established scenario)")
    r("2 Circles","Circles card",f"{name} ring","Missing data",missing,"Shown as specified (New user scenario)")
    r("2 Circles","Circles card",f"{name} ring","Loading","Track with spinner and 'Loading'","Shown (Loading scenario)")
    r("2 Circles","Circles card",f"{name} ring","Tap",f"Opens detail: {det}","Opens a sample detail sheet with Close")
    r("2 Circles","Circles card",f"{name} ring","Large text","Rings become a list with full-width text","List layout at accessibility sizes")
r("3 Getting Started","Getting Started card","Position","Essential step open","Directly below the circles, list expanded","Shown below the circles (New user scenario)")
r("3 Getting Started","Getting Started card","Position","All essential steps done","At the bottom of Home, collapsed 'Setup complete'","Moves to the bottom when both essential steps are ticked")
r("3 Getting Started","Getting Started card","Header row","Tap","Expands / collapses the list","Works locally")
r("3 Getting Started","Getting Started card","Progress bar","Normal","Done ÷ total","Shown")
r("3 Getting Started","Getting Started card","Step row","Tap","Opens that step's destination","Toggles done locally (prototype stand-in)")
r("3 Getting Started","Getting Started card","Step row","Done","Green tick and strikethrough","Shown")
r("3 Getting Started","Getting Started card","Step row","Optional","'Optional' label","Shown")
r("4 Seven-day strip","Strip card","Day cell","Normal","Weekday letter, sport icon(s), status icon","Shown for 7 days")
r("4 Seven-day strip","Strip card","Day cell","Today","Outlined and tinted","Shown")
r("4 Seven-day strip","Strip card","Day cell","Two sessions","Two stacked sport icons","Shown (Wednesday in the sample)")
r("4 Seven-day strip","Strip card","Day cell","Rest","Moon icon","Shown")
r("4 Seven-day strip","Strip card","Day cell","Tap","Opens the Day page","Opens a sample day sheet")
r("4 Seven-day strip","Strip card","Strip","Empty","'No plan for this week yet.'","Shown in the gallery")
r("4 Seven-day strip","Strip card","Strip","Loading","Seven placeholder cells","Shown (Loading scenario)")
for card, normal, empty in [("Endurance card","Time done, 'of planned', bar, distance, 8-week sparkline","'No rides yet…' message"),
                            ("Strength Load card","'n of m sessions completed', bar, volume, sparkline","True zero count and 'Trend appears after two weeks…'")]:
    r("5 Sport cards",card,"Whole card","Normal",normal,"Shown (Established scenario)")
    r("5 Sport cards",card,"Whole card","Empty / insufficient data",empty,"Shown (New user scenario)")
    r("5 Sport cards",card,"Whole card","Loading","Placeholder blocks","Shown (Loading scenario)")
    r("5 Sport cards",card,"Whole card","Tap","Opens Progress for that sport","Opens a sample sheet with weekly bars")
r("5 Sport cards","Both cards","Layout","Large text","Cards stack vertically","Stacks at accessibility sizes")
r("6 Coach","Coach row","Sentence","Normal","One sentence from the rules-based coach","Sample sentence shown, labelled rules-based")
r("6 Coach","Coach row","Why? button","Tap","Opens the explanation","Opens a sample explanation sheet")
r("6 Coach","Coach row","Review button","Proposal present","Opens review and approval","Opens the review sheet")
r("6 Coach","Coach row","Not now button","Proposal present","Postpones without declining","Shows a sample toast")
r("6 Coach","Coach row","Row","No suggestion","Explains what the coach is waiting for","Shown (New user scenario)")
r("6 Coach","Coach row","Row","Loading","Placeholder lines","Shown (Loading scenario)")
r("6 Coach","Review sheet","Approve","Tap","Applies the change","Closes with 'Sample only — nothing was changed.'")
r("6 Coach","Review sheet","Not now","Tap","Postpones","Closes with a sample toast")
r("6 Coach","Review sheet","Decline","Tap","Declines","Closes with a sample toast")
r("6 Coach","Review sheet","Approve","Blocked","Disabled, with the reason shown","Shown in the gallery (Sheets)")
r("7 Trends","Trends card","Series chips","Tap","Shows / hides a series; one always stays on","Works locally")
r("7 Trends","Trends card","Consistency line","Normal","Percentage per day; missing days leave a gap","Shown; future days empty")
r("7 Trends","Trends card","Load Balance row","Normal","One status cell per day, words not numbers","Shown")
r("7 Trends","Trends card","Recovery row","Normal","One status cell per day, words not numbers","Shown")
r("7 Trends","Trends card","Chart / day cell","Touch","Selects the day and shows a readout","Works locally")
r("7 Trends","Trends card","Card","Empty","'Trends appear once you have completed sessions…'","Shown (New user scenario)")
r("7 Trends","Trends card","Card","Loading","Placeholder block","Shown (Loading scenario)")
r("7 Trends","Trends card","Chart","VoiceOver","Spoken summary of each series","Summary text provided; not yet heard on a real iPhone","Real-device VoiceOver check outstanding")
r("Navigation","Tab bar","Home tab","Selected","Accent colour","Shown")
r("Navigation","Tab bar","Plan / Progress tabs","Tap","Open their screens","Show 'not prototyped yet'")
r("Navigation","Tab bar","Centre 'Train now'","Tap","Opens the Training Hub","Opens a placeholder sheet")
r("Navigation","Tab bar","Centre badge","Normal","Number of sessions today","Sample count shown")
for t in ["Obsidian","Arctic","Ocean","Forest","Sandstone","High Contrast"]:
    r("Themes","Whole screen",f"{t} theme","Normal","All tokens applied; meanings unchanged; contrast ≥ 4.5:1 for text","Screenshot captured; contrast check passed for the token pairs")
r("Themes","Lab","Theme switch","Tap","Whole prototype updates immediately","Works locally")

out = pathlib.Path(__file__).resolve().parents[1] / "docs"
head = ["Page","Section","Card","Control","State","Expected behaviour","Actual prototype behaviour","Issue","Approval status"]
with open(out / "HOME_V2_REVIEW_TRACKER.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(head); w.writerows(rows)
md = ["# Home v2 — review tracker (prototype)", "",
      "Page → Section → Card → Control → State → Expected behaviour → Actual prototype behaviour → Issue → Approval status.",
      "", "**No row is approved.** Only the owner changes the last column. \"Actual prototype behaviour\" describes the",
      "UI Lab build in the simulator; it is not evidence about the production app or a physical iPhone.", "",
      "| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
md += ["| " + " | ".join(c.replace("|", "/") for c in row) + " |" for row in rows]
md += ["", f"Rows: {len(rows)}"]
(out / "HOME_V2_REVIEW_TRACKER.md").write_text("\n".join(md) + "\n")
print(len(rows), "rows")
