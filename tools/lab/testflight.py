#!/usr/bin/env python3
"""Cyclift Lab only: internal TestFlight group, the account holder as its tester, and the processing state of one build.

Works solely on the app whose identifier is com.ralsuwaidico.cycliftlab. It never reads or changes any other app, its
groups or its testers. Internal group only: nothing here can distribute externally or publicly.
"""
import os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "ios", "ci"))
import asc

IDENT = "com.ralsuwaidico.cycliftlab"
GROUP = "Cyclift Lab internal"

def main():
    asc.TOKEN = asc.token()
    n = os.environ.get("BUILD_NUMBER", "").strip(); commit = os.environ.get("COMMIT", "").strip()[:8]
    st, res = asc.call("GET", "/v1/apps", query={"filter[bundleId]": IDENT, "limit": 5})
    apps = [a for a in res.get("data", []) if a["attributes"].get("bundleId") == IDENT] if st == 200 else []
    if len(apps) != 1:
        raise SystemExit(f"Cyclift Lab app entry not found exactly once (HTTP {st})")
    app_id = apps[0]["id"]; print(f"app entry: {apps[0]['attributes'].get('name')} ({IDENT})")
    # internal group
    st, res = asc.call("GET", f"/v1/apps/{app_id}/betaGroups", query={"limit": 50})
    groups = res.get("data", []) if st == 200 else []
    group = next((g for g in groups if g["attributes"].get("isInternalGroup") and g["attributes"].get("name") == GROUP), None)
    if group is None:
        st, res = asc.call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {"name": GROUP, "isInternalGroup": True, "hasAccessToAllBuilds": True},
                                                               "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        if st not in (200, 201): raise SystemExit(f"Could not create the internal group (HTTP {st}): {asc.errors_text(res)}")
        group = res["data"]; print(f"internal group '{GROUP}': created")
    else: print(f"internal group '{GROUP}': already exists")
    ext = [g["attributes"].get("name") for g in groups if not g["attributes"].get("isInternalGroup")]
    print(f"external groups on Cyclift Lab: {len(ext)}")
    # the account holder as the only tester added here
    st, res = asc.call("GET", "/v1/users", query={"limit": 50})
    if st != 200: raise SystemExit(f"Could not list users (HTTP {st})")
    st2, cur = asc.call("GET", f"/v1/betaGroups/{group['id']}/betaTesters", query={"limit": 200})
    have = {t["attributes"].get("email", "").lower() for t in cur.get("data", [])} if st2 == 200 else set()
    holders = [u["attributes"] for u in res.get("data", []) if "ACCOUNT_HOLDER" in (u["attributes"].get("roles") or [])]
    added = 0
    for a in holders:
        email = (a.get("username") or "").strip()
        if not email or email.lower() in have: continue
        st3, r3 = asc.call("POST", "/v1/betaTesters", {"data": {"type": "betaTesters", "attributes": {"email": email, "firstName": a.get("firstName") or "", "lastName": a.get("lastName") or ""},
                                                                "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}}}})
        if st3 in (200, 201): added += 1
        else: print(f"could not add the account holder as tester (HTTP {st3}): {asc.errors_text(r3)}")
    print(f"testers in the group: {len(have)} before, account holder added now: {added} (account holders found: {len(holders)})")
    if not n: return
    build = None; deadline = time.time() + 35 * 60
    while time.time() < deadline:
        st, res = asc.call("GET", "/v1/builds", query={"filter[app]": app_id, "filter[version]": n, "limit": 5})
        if st == 200 and res.get("data"):
            build = res["data"][0]; state = build["attributes"].get("processingState")
            if state in ("VALID", "FAILED", "INVALID"): break
            print(f"  build {n}: processing ({state})", flush=True)
        else: print(f"  build {n}: not visible in App Store Connect yet", flush=True)
        time.sleep(60)
    if build is None: print(f"RESULT testflight: build {n} did not appear within 35 min"); return
    state = build["attributes"].get("processingState")
    if state != "VALID": print(f"RESULT testflight: build {n} processing state {state} — not installable"); return
    text = (f"CYCLIFT LAB — internal preview, demo data only. Build {n}, commit {commit}. Not a release of Cyclift and not final design.\n\n"
            "WHAT IT IS: the redesigned Cyclift on a made-up demo athlete. It cannot reach your real Cyclift data, Apple Health, "
            "Bluetooth sensors, GPS or any account. Everything you do stays inside this app; Profile > Data, Help & About can delete it or restore the demo.\n\n"
            "NEW SINCE BUILD 4: Plan follows the approved B1 sheet with the header glow corrected; Home, Plan and the Coach page now show the same Coach item, "
            "and a finding is no longer labelled as a suggestion to review; the Lab tag is compact and pages clear the bottom bar.\n\n"
            "TRY: Home and its pages; Plan; the Train ball > today's strength session > Start > log sets > minimise and resume > Finish > Save > optional review; "
            "the Coach page; Progress; Profile and the six themes; onboarding after deleting the data.\n\n"
            "HOW IT WAS CHECKED: Lab run 43 on this exact commit passed 12 of 13 simulator checks, and the signed build passed its isolation check. The one failed "
            "check had a mistake in the check itself; because of it, the last step of the Coach's Not now sequence (opening the approval sheet and accepting) "
            "was NOT tested on this commit.\n\n"
            "KNOWN LIMITATIONS: Home v2.3 is provisional, not an approved design. Coach 'Not now' is incomplete: on the Coach page it postpones the suggestion, but on "
            "the approval sheet the same button still dismisses it; the demo athlete normally has no open suggestion, so you may not meet it at all. "
            "Cycling is a labelled demonstration with simulated figures and saves nothing. The Coach follows written rules; AI chat is not connected. "
            "Progress shows no stage (stage criteria are not approved) and draws its ring more simply than the approved sheet. Profile's inner pages are the older screens. "
            "Plan was not re-checked on smaller iPhones or at large text sizes. Apple Watch, devices, Arabic and data import are not in this build. "
            "Tested only in the iOS Simulator before this build: please report anything that looks or behaves wrong on your iPhone.")
    st, res = asc.call("GET", f"/v1/builds/{build['id']}/betaBuildLocalizations", query={"limit": 20})
    locs = res.get("data", []) if st == 200 else []
    if locs: st, res = asc.call("PATCH", f"/v1/betaBuildLocalizations/{locs[0]['id']}", {"data": {"type": "betaBuildLocalizations", "id": locs[0]["id"], "attributes": {"whatsNew": text}}})
    else: st, res = asc.call("POST", "/v1/betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": text},
                                                                            "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
    st4, r4 = asc.call("GET", f"/v1/builds/{build['id']}/buildBetaDetail")
    istate = r4.get("data", {}).get("attributes", {}).get("internalBuildState") if st4 == 200 else None
    print(f"RESULT testflight: build {n} processed (VALID); internal testing state: {istate}; What to Test {'set' if st in (200, 201) else 'NOT set'}")

if __name__ == "__main__":
    main()
