import json, csv, os, sys, glob
sys.path.insert(0, os.path.dirname(__file__))
from rules import R
OUT = sys.argv[1]; DST = sys.argv[2]; DATE = "2026-10-27"; COMMIT = "2b2c104"

def wk(ws):
    parts = []
    for w in ws:
        if w['kind'] == 'rest': parts.append(f"{w['date'][:3]} rest"); continue
        s = f"{w['date'][:3]} {w['title']} {w['minutes']}m" + (" FIXED" if w['fixed'] else "") + (f" [{w['intervalReps']} reps]" if w.get('intervalReps') else "")
        if w['coachAdjusted']: s += f" (coach-adjusted; was {w.get('original')})"
        if w['entries']:
            s += " {" + "; ".join(f"{e['name']} {len(e['sets'])}x{e['sets'][0]['reps']}" + (f"@{e['sets'][0]['kg']}kg" if e['sets'][0].get('kg') is not None else ("" if not e['sets'][0].get('bw') else " BW")) + (f" RPE{e['targetRPE']}" if e.get('targetRPE') else "") for e in w['entries']) + "}"
        parts.append(s)
    return " | ".join(parts)

rows = []
for f in sorted(glob.glob(os.path.join(OUT, "P*.json"))):
    r = json.load(open(f))
    crit = r['criteria']
    failed = [c for c in crit if not c['pass']]
    counted = [c for c in crit if c['kind'] != 'science-advisory']
    inp = r['inputs']
    key = "; ".join(f"{k}={inp[k]}" for k in ['trainingMode','priority','hybridGoal','level','cyclingSessions','liftSessions','trainingDaysPerWeek','cyclingBudget_h','liftingBudget_h','strengthSplit','strengthSessionMinutes','cyclingSessionMinutes','age','equipment','sensor','units','autoAdapt','historyDays','planner.experience(effective)','planner.goal(effective)'] if k in inp)
    performed = len([h for h in r['simulatedHistory'] if 'MISSED' not in h]); missed = len([h for h in r['simulatedHistory'] if 'MISSED' in h])
    rows.append(dict(audited_commit=COMMIT, audit_date=DATE, case_id=r['id'], kind="profile (end-to-end Store pipeline)", title=r['title'], athlete_type=r['athleteType'],
        inputs=key, availability=" | ".join(r['availability']), generated_next_week=wk(r['nextWeek']),
        simulated_history=f"{performed} sessions performed, {missed} missed over {inp.get('historyDays')} days; last: " + " || ".join(r['simulatedHistory'][-3:]),
        feedback=r['feedback'],
        final_adjustments=" || ".join(f"{a['date']} {a['workout']}: {a['summary'] if 'summary' in a else a['change']} [{a['category']}] — {a['why'][:220]}" for a in r['finalAdjustments']) or "none",
        proposals=" || ".join(f"{p['reason']}: {p['text']}" for p in r['finalProposals']) or "none",
        confidence=r['confidence'], findings=" || ".join(x[:200] for x in r['findings']),
        schedule_messages=" | ".join(r['consistency'] + r['hybridFindingsNextWeek']) or "none",
        criteria_passed=f"{sum(1 for c in counted if c['pass'])}/{len(counted)} counted (+{sum(1 for c in crit if c['kind']=='science-advisory' and c['pass'])}/{sum(1 for c in crit if c['kind']=='science-advisory')} advisory)",
        criteria_failed=" || ".join(f"{c['id']} [{c['kind']}]: {c['detail'][:300]}" for c in failed) or "none",
        result="PASS" if r['pass'] else "FAIL"))
pr = json.load(open(os.path.join(OUT, "probes.json")))
for p in pr:
    rows.append(dict(audited_commit=COMMIT, audit_date=DATE, case_id=p['id'], kind="rule probe (direct call of the real function)", title=p['rule'], athlete_type="n/a", inputs=p['input'], availability="", generated_next_week="",
        simulated_history="", feedback="", final_adjustments=p['observed'], proposals="", confidence="", findings="", schedule_messages="", criteria_passed="", criteria_failed="" if p['pass'] else f"expected: {p['expected']} (code: {p['codeRef']})",
        result="PASS" if p['pass'] else "FAIL"))
with open(os.path.join(DST, "CYCLIFT_COACH_TEST_CASES.csv"), "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
with open(os.path.join(DST, "CYCLIFT_COACH_RULES.csv"), "w", newline="") as fh:
    fields = ["audited_commit","audit_date","rule_id","area","rule","thresholds","source","source_type","reference_verified","code_location","confidence","limitations"]
    w = csv.DictWriter(fh, fieldnames=fields); w.writeheader()
    for x in R: w.writerow(dict(audited_commit=COMMIT, audit_date=DATE, **x))
print(len(rows), "test rows;", len(R), "rules")
