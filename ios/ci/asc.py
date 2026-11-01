#!/usr/bin/env python3
"""App Store Connect setup for BikeComputer, run by CI (never by hand).

Uses the App Store Connect API key from CI secrets (environment variables, never arguments or files in the repo):
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY (contents of the .p8 file)

What it does, idempotently:
  1. Registers the iPhone and Watch bundle IDs (if missing) and enables HealthKit on both.
  2. Checks that the App Store Connect app record exists (Apple does not allow creating it through the API).
  3. Creates a private internal TestFlight group that gets every build automatically and adds the
     account holder / admins to it (internal testers only: no Apple review, nothing public).
  4. Keeps a second internal group "Internal QA" (every build, no testers added automatically — the owner adds them)
     for evaluating internal test builds separately from approved releases.

`asc.py testflight` (run after an upload, env BUILD_NUMBER and COMMIT): waits for Apple's processing of that build
(up to ~40 min), reports its state, and sets the TestFlight "What to Test" text to
"INTERNAL TEST BUILD <n> — not an approved release …" (plus ios/TESTFLIGHT_NOTES.txt when present).

The repository is public, so this script never prints e-mail addresses, names, team IDs or key material.
Writes `app_ready=true|false` to $GITHUB_OUTPUT.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com"
APP_BUNDLE = "com.ralsuwaidico.bikecomputer"
BUNDLES = [
    (APP_BUNDLE, "BikeComputer iPhone"),
    (APP_BUNDLE + ".watchkitapp", "BikeComputer Watch"),
]
GROUP_NAME = "Rashed devices"
QA_GROUP_NAME = "Internal QA"


def log(msg):
    print(msg, flush=True)


def gh_output(key, value):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as f:
            f.write(f"{key}={value}\n")


def token():
    key = os.environ["ASC_PRIVATE_KEY"].strip().replace("\\n", "\n")
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"].strip(), "typ": "JWT"},
    )


TOKEN = None


def call(method, path, body=None, query=None):
    url = API + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            payload = json.loads(raw)
        except Exception:
            payload = {"raw": raw[:500].decode(errors="replace")}
        return e.code, payload


def errors_text(payload):
    errs = payload.get("errors") or []
    return "; ".join(f"{e.get('code')}: {e.get('detail') or e.get('title')}" for e in errs) or str(payload)[:300]


def ensure_bundle(identifier, name):
    st, res = call("GET", "/v1/bundleIds", query={"filter[identifier]": identifier, "limit": 50})
    if st != 200:
        txt = errors_text(res)
        if "agreement" in txt.lower() or "PLA" in txt:
            raise SystemExit("Apple is waiting for the account holder to accept the updated Program License Agreement: "
                             "sign in at developer.apple.com/account, accept the agreement banner, then run again. "
                             f"(HTTP {st}: {txt})")
        raise SystemExit(f"Could not list bundle IDs (HTTP {st}): {txt}")
    match = [b for b in res.get("data", []) if b["attributes"]["identifier"] == identifier]
    if match:
        bid = match[0]["id"]
        log(f"  bundle ID {identifier}: already registered")
    else:
        st, res = call("POST", "/v1/bundleIds", {
            "data": {"type": "bundleIds", "attributes": {"identifier": identifier, "name": name, "platform": "IOS"}}
        })
        if st not in (200, 201):
            raise SystemExit(f"Could not register bundle ID {identifier} (HTTP {st}): {errors_text(res)}")
        bid = res["data"]["id"]
        log(f"  bundle ID {identifier}: registered now")

    st, res = call("GET", f"/v1/bundleIds/{bid}/bundleIdCapabilities")
    caps = {c["attributes"]["capabilityType"] for c in res.get("data", [])} if st == 200 else set()
    if "HEALTHKIT" in caps:
        log(f"  HealthKit on {identifier}: already enabled")
    else:
        st, res = call("POST", "/v1/bundleIdCapabilities", {
            "data": {
                "type": "bundleIdCapabilities",
                "attributes": {"capabilityType": "HEALTHKIT"},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}},
            }
        })
        if st not in (200, 201):
            raise SystemExit(f"Could not enable HealthKit on {identifier} (HTTP {st}): {errors_text(res)}")
        log(f"  HealthKit on {identifier}: enabled now")


def find_app():
    st, res = call("GET", "/v1/apps", query={"filter[bundleId]": APP_BUNDLE, "limit": 10})
    if st != 200:
        raise SystemExit(f"Could not list apps (HTTP {st}): {errors_text(res)}")
    for a in res.get("data", []):
        if a["attributes"].get("bundleId") == APP_BUNDLE:
            return a["id"]
    return None


def ensure_group(app_id):
    st, res = call("GET", f"/v1/apps/{app_id}/betaGroups", query={"limit": 50})
    if st != 200:
        log(f"::warning::Could not read TestFlight groups (HTTP {st}): {errors_text(res)}")
        return
    group = None
    for g in res.get("data", []):
        a = g["attributes"]
        if a.get("isInternalGroup") and a.get("name") == GROUP_NAME:
            group = g
    if group is None:
        st, res = call("POST", "/v1/betaGroups", {
            "data": {
                "type": "betaGroups",
                "attributes": {"name": GROUP_NAME, "isInternalGroup": True, "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        if st not in (200, 201):
            log(f"::warning::Could not create the internal TestFlight group (HTTP {st}): {errors_text(res)}. "
                "It can be created by hand in App Store Connect > TestFlight > Internal Testing.")
            return
        group = res["data"]
        log(f"  TestFlight internal group '{GROUP_NAME}': created (gets every build automatically)")
    else:
        log(f"  TestFlight internal group '{GROUP_NAME}': already exists")

    # Internal testers must be App Store Connect users. Add the account holder and admins.
    st, res = call("GET", "/v1/users", query={"limit": 50})
    if st != 200:
        log(f"::warning::Could not list App Store Connect users (HTTP {st}); add yourself to the group by hand.")
        return
    st2, current = call("GET", f"/v1/betaGroups/{group['id']}/betaTesters", query={"limit": 200})
    have = {t["attributes"].get("email", "").lower() for t in current.get("data", [])} if st2 == 200 else set()
    added = 0
    for u in res.get("data", []):
        a = u["attributes"]
        roles = set(a.get("roles") or [])
        email = (a.get("username") or "").strip()
        if not email or not roles & {"ACCOUNT_HOLDER", "ADMIN"}:
            continue
        if email.lower() in have:
            continue
        st3, r3 = call("POST", "/v1/betaTesters", {
            "data": {
                "type": "betaTesters",
                "attributes": {"email": email, "firstName": a.get("firstName") or "", "lastName": a.get("lastName") or ""},
                "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}},
            }
        })
        if st3 in (200, 201):
            added += 1
        else:
            log(f"::warning::Could not add an internal tester automatically (HTTP {st3}): {errors_text(r3)}")
    log(f"  internal testers: {len(have)} already in the group, {added} added now")


def ensure_qa_group(app_id):
    """Internal QA group: internal, gets every build, no testers added by CI (existing membership untouched)."""
    st, res = call("GET", f"/v1/apps/{app_id}/betaGroups", query={"limit": 50})
    if st != 200:
        log(f"::warning::Could not read TestFlight groups (HTTP {st}): {errors_text(res)}")
        return
    if any(g["attributes"].get("isInternalGroup") and g["attributes"].get("name") == QA_GROUP_NAME for g in res.get("data", [])):
        log(f"  TestFlight internal group '{QA_GROUP_NAME}': already exists")
        return
    st, res = call("POST", "/v1/betaGroups", {
        "data": {
            "type": "betaGroups",
            "attributes": {"name": QA_GROUP_NAME, "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    })
    if st in (200, 201):
        log(f"  TestFlight internal group '{QA_GROUP_NAME}': created (no testers added automatically)")
    else:
        log(f"::warning::Could not create the '{QA_GROUP_NAME}' group (HTTP {st}): {errors_text(res)}. "
            "It can be created by hand in App Store Connect > TestFlight > Internal Testing.")


def testflight_report(app_id):
    """After an upload: wait for processing, report readiness, set the What to Test text."""
    n = os.environ.get("BUILD_NUMBER", "").strip()
    commit = os.environ.get("COMMIT", "").strip()[:7]
    if not n:
        log("No BUILD_NUMBER given."); return 1
    build = None
    deadline = time.time() + 40 * 60
    while time.time() < deadline:
        st, res = call("GET", "/v1/builds", query={"filter[app]": app_id, "filter[version]": n, "limit": 5})
        if st == 200 and res.get("data"):
            build = res["data"][0]
            state = build["attributes"].get("processingState")
            if state in ("VALID", "FAILED", "INVALID"):
                break
            log(f"  build {n}: processing ({state})")
        else:
            log(f"  build {n}: not visible in App Store Connect yet")
        time.sleep(60)
    if build is None:
        log(f"RESULT testflight: build {n} did not appear in App Store Connect within 40 min (check again later)")
        return 0
    state = build["attributes"].get("processingState")
    if state != "VALID":
        log(f"RESULT testflight: build {n} processing state {state} — not installable yet")
        return 0
    text = f"INTERNAL TEST BUILD {n} — not an approved release. Commit {commit}."
    notes = os.path.join(os.path.dirname(__file__), "..", "TESTFLIGHT_NOTES.txt")
    if os.path.exists(notes):
        with open(notes, encoding="utf-8") as fh:
            text += "\n\n" + fh.read().strip()
    text = text[:3900]
    st, res = call("GET", f"/v1/builds/{build['id']}/betaBuildLocalizations", query={"limit": 20})
    locs = res.get("data", []) if st == 200 else []
    loc = next((l for l in locs if l["attributes"].get("locale", "").startswith("en")), locs[0] if locs else None)
    if loc:
        st, res = call("PATCH", f"/v1/betaBuildLocalizations/{loc['id']}", {
            "data": {"type": "betaBuildLocalizations", "id": loc["id"], "attributes": {"whatsNew": text}}})
    else:
        st, res = call("POST", "/v1/betaBuildLocalizations", {
            "data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": text},
                     "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
    notes_ok = st in (200, 201)
    if not notes_ok:
        log(f"::warning::Could not set What to Test (HTTP {st}): {errors_text(res)}")
    log(f"RESULT testflight: build {n} processed (VALID) — installable by internal testers in TestFlight; "
        f"What to Test {'set' if notes_ok else 'NOT set'}")
    return 0


def main():
    global TOKEN
    missing = [k for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY") if not os.environ.get(k, "").strip()]
    if missing:
        log("::warning::App Store Connect secrets are not set yet (" + ", ".join(missing) + "). "
            "Skipping Apple setup; the apps are still compiled and tested.")
        gh_output("app_ready", "false")
        gh_output("secrets", "false")
        return 0
    gh_output("secrets", "true")
    TOKEN = token()
    log("Bundle IDs and capabilities:")
    for ident, name in BUNDLES:
        ensure_bundle(ident, name)
    app_id = find_app()
    if not app_id:
        log("::warning::The App Store Connect app record for com.ralsuwaidico.bikecomputer does not exist yet. "
            "Create it once at appstoreconnect.apple.com > Apps > + > New App (see ios/SETUP.md). "
            "Until then builds are compiled and signed-checked but not uploaded.")
        gh_output("app_ready", "false")
        return 0
    log("App Store Connect app record: found")
    if len(sys.argv) > 1 and sys.argv[1] == "testflight":
        return testflight_report(app_id)
    ensure_group(app_id)
    ensure_qa_group(app_id)
    gh_output("app_ready", "true")
    return 0


if __name__ == "__main__":
    sys.exit(main())
