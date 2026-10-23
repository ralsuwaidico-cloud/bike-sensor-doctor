#!/usr/bin/env python3
"""App Store Connect setup for BikeComputer, run by CI (never by hand).

Uses the App Store Connect API key from CI secrets (environment variables, never arguments or files in the repo):
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY (contents of the .p8 file)

What it does, idempotently:
  1. Registers the iPhone and Watch bundle IDs (if missing) and enables HealthKit on both.
  2. Checks that the App Store Connect app record exists (Apple does not allow creating it through the API).
  3. Creates a private internal TestFlight group that gets every build automatically and adds the
     account holder / admins to it (internal testers only: no Apple review, nothing public).

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
        raise SystemExit(f"Could not list bundle IDs (HTTP {st}): {errors_text(res)}")
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
        print(f"::add-mask::{email}", flush=True)
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
    ensure_group(app_id)
    gh_output("app_ready", "true")
    return 0


if __name__ == "__main__":
    sys.exit(main())
