#!/usr/bin/env python3
"""Cyclift Lab: registers the Lab app identifier with Apple (owner request, 16 Nov 2026) and reports its capabilities.

Registers ONLY com.ralsuwaidico.cycliftlab, as an explicit iOS identifier. It enables no capability: no HealthKit,
no Sign in with Apple, no app groups, no iCloud. It creates no app record, uploads nothing and touches no other
identifier. Reuses the request helpers of ios/ci/asc.py.
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "ios", "ci"))
import asc

IDENT = "com.ralsuwaidico.cycliftlab"
NAME = "Cyclift Lab"

def main():
    if not all(os.environ.get(k) for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY")):
        raise SystemExit("Apple credentials are not available to this run.")
    asc.TOKEN = asc.token()
    st, res = asc.call("GET", "/v1/bundleIds", query={"filter[identifier]": IDENT, "limit": 50})
    if st != 200:
        raise SystemExit(f"Could not list identifiers (HTTP {st}): {asc.errors_text(res)}")
    match = [b for b in res.get("data", []) if b["attributes"]["identifier"] == IDENT]
    if match:
        bid = match[0]["id"]; print(f"identifier {IDENT}: already registered")
    else:
        st, res = asc.call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": IDENT, "name": NAME, "platform": "IOS"}}})
        if st not in (200, 201):
            raise SystemExit(f"Could not register {IDENT} (HTTP {st}): {asc.errors_text(res)}")
        bid = res["data"]["id"]; print(f"identifier {IDENT}: registered now, name '{NAME}'")
    st, res = asc.call("GET", f"/v1/bundleIds/{bid}/bundleIdCapabilities")
    caps = sorted(c["attributes"]["capabilityType"] for c in res.get("data", [])) if st == 200 else None
    print(f"capabilities on {IDENT}: {caps if caps is not None else 'could not be read'}")
    sensitive = {"HEALTHKIT", "APP_GROUPS", "ICLOUD", "APPLE_ID_AUTH", "PUSH_NOTIFICATIONS", "ASSOCIATED_DOMAINS"}
    if caps and sensitive & set(caps):
        raise SystemExit(f"UNEXPECTED capabilities on the Lab identifier: {sorted(sensitive & set(caps))}")
    st, res = asc.call("GET", "/v1/apps", query={"filter[bundleId]": IDENT, "limit": 5})
    found = st == 200 and any(a["attributes"].get("bundleId") == IDENT for a in res.get("data", []))
    print(f"App Store Connect app entry for {IDENT}: {'found' if found else 'not created yet'}")

if __name__ == "__main__":
    main()
