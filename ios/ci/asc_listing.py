#!/usr/bin/env python3
"""App Store Connect listing preparation for Cyclift 1.0 — DRAFTS ONLY. Run by .github/workflows/asc-listing.yml.

MODE=check  read-only: reports the app record, name, version, localizations, capabilities, screenshots, builds.
MODE=apply  writes draft metadata to the version that is still being prepared (never submits, never releases,
            never touches pricing, availability or agreements):
              - enables Sign in with Apple (APPLE_ID_AUTH) on the app's bundle ID (HealthKit stays)
              - app name (first accepted candidate), subtitle, privacy policy URL, categories, age rating
              - version 1.0.0 (created only if no editable version exists), copyright
              - description, keywords, promotional text, support + marketing URLs
              - App Review notes, demo account not required (contact fields are left for the owner)
              - screenshots from $SCREENSHOT_DIR into the 6.9" iPhone set (replaces only files this script uploaded)

Inputs (environment): ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY (secrets), MODE, SCREENSHOT_DIR (optional),
REPORT (path of the report file). The repository is public: the report never contains e-mail addresses, personal
names, phone numbers, team IDs or key material (contact fields are reported only as "set"/"empty").
"""
import hashlib
import os
import re
import struct
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402  (token(), call(), errors_text(), find_app())

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
STORE = os.path.join(ROOT, "store", "en-US")
MODE = os.environ.get("MODE", "check").strip().lower()
APPLY = MODE == "apply"
SHOT_DIR = os.environ.get("SCREENSHOT_DIR", "").strip()
REPORT = os.environ.get("REPORT", "asc-listing-report.txt")
SHOT_PREFIX = "cyclift-store-"
OLD_SHOT_PREFIXES = ("athletics-store-",)   # earlier uploads by this script (pre-rename) are replaced too
TARGET_VERSION = "1.0.0"
EDITABLE_INFO = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
EDITABLE_VERSION = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}

EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
LINES = []
PROBLEMS = []


def out(msg=""):
    msg = EMAIL.sub("<e-mail hidden>", str(msg))
    LINES.append(msg)
    print(msg, flush=True)


def problem(msg):
    PROBLEMS.append(EMAIL.sub("<e-mail hidden>", msg))
    out("  ! " + msg)


def shown_name(n):
    """The current store name may contain the owner's personal name: show it only when it is one of our candidates."""
    try:
        cands = [c.strip() for c in read("name_candidates.txt").splitlines() if c.strip()]
    except OSError:
        cands = []
    return f"'{n}'" if n in cands else f"(not a Cyclift candidate yet, {len(n or '')} characters — hidden)"


def read(name):
    with open(os.path.join(STORE, name), encoding="utf-8") as f:
        return f.read().strip()


def kv(name):
    d = {}
    for line in read(name).splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            d[k.strip()] = v.strip()
    return d


def err(res):
    return EMAIL.sub("<e-mail hidden>", asc.errors_text(res))


def call(method, path, body=None, query=None):
    return asc.call(method, path, body, query)


def patch(kind, ident, attributes=None, relationships=None):
    data = {"type": kind, "id": ident}
    if attributes:
        data["attributes"] = attributes
    if relationships:
        data["relationships"] = relationships
    return call("PATCH", f"/v1/{kind}/{ident}", {"data": data})


def state_of(attrs, *keys):
    for k in keys:
        if attrs.get(k):
            return attrs[k]
    return "?"


# ------------------------------------------------------------------------------------------------ capability
def sign_in_with_apple():
    out("Sign in with Apple capability on " + asc.APP_BUNDLE + ":")
    st, res = call("GET", "/v1/bundleIds", query={"filter[identifier]": asc.APP_BUNDLE, "limit": 50})
    if st != 200:
        problem(f"could not read bundle IDs (HTTP {st}): {err(res)}")
        return
    match = [b for b in res.get("data", []) if b["attributes"]["identifier"] == asc.APP_BUNDLE]
    if not match:
        problem("bundle ID not registered (the iOS workflow registers it)")
        return
    bid = match[0]["id"]
    st, res = call("GET", f"/v1/bundleIds/{bid}/bundleIdCapabilities")
    caps = {c["attributes"]["capabilityType"] for c in res.get("data", [])} if st == 200 else set()
    out("  capabilities now: " + (", ".join(sorted(caps)) or "none"))
    if "APPLE_ID_AUTH" in caps:
        out("  Sign in with Apple: already enabled")
        return
    if not APPLY:
        out("  Sign in with Apple: NOT enabled (apply mode enables it)")
        return
    st, res = call("POST", "/v1/bundleIdCapabilities", {"data": {
        "type": "bundleIdCapabilities",
        "attributes": {"capabilityType": "APPLE_ID_AUTH",
                       "settings": [{"key": "APPLE_ID_AUTH_APP_CONSENT", "options": [{"key": "PRIMARY_APP_CONSENT"}]}]},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})
    if st in (200, 201):
        out("  Sign in with Apple: enabled now")
    else:
        problem(f"could not enable Sign in with Apple (HTTP {st}): {err(res)}")


# ------------------------------------------------------------------------------------------------ app info
def app_info(app_id, primary_locale):
    st, res = call("GET", f"/v1/apps/{app_id}/appInfos", query={"limit": 10})
    if st != 200:
        problem(f"could not read app infos (HTTP {st}): {err(res)}")
        return None
    infos = res.get("data", [])
    for i in infos:
        out(f"  app info {i['id'][:8]}…: state {state_of(i['attributes'], 'state', 'appStoreState')}")
    editable = [i for i in infos if state_of(i["attributes"], "state", "appStoreState") in EDITABLE_INFO]
    if not editable:
        problem("no editable app info (the app name/category are locked while a version is in review or live)")
        return None
    info = editable[0]
    iid = info["id"]

    # localization (name, subtitle, privacy URL)
    st, res = call("GET", f"/v1/appInfos/{iid}/appInfoLocalizations", query={"limit": 50})
    locs = res.get("data", []) if st == 200 else []
    loc = next((l for l in locs if l["attributes"].get("locale") == primary_locale), None) \
        or next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)
    if loc is None:
        problem(f"no app info localization for {primary_locale} (HTTP {st}: {err(res) if st != 200 else 'empty'})")
    else:
        a = loc["attributes"]
        out(f"  locale {a.get('locale')}: name {shown_name(a.get('name'))}, subtitle '{a.get('subtitle') or ''}', "
            f"privacy URL {'set' if a.get('privacyPolicyUrl') else 'empty'}")
        if APPLY:
            names = [n.strip() for n in read("name_candidates.txt").splitlines() if n.strip()]
            accepted = None
            if a.get("name") in names:
                accepted = a.get("name")
                out(f"  name: already '{accepted}'")
            else:
                for n in names:
                    st2, r2 = patch("appInfoLocalizations", loc["id"], {"name": n})
                    if st2 == 200:
                        accepted = n
                        out(f"  name: '{n}' ACCEPTED")
                        break
                    out(f"  name: '{n}' rejected (HTTP {st2}): {err(r2)}")
                if not accepted:
                    problem("none of the name candidates was accepted — pick another name (ios/store/en-US/name_candidates.txt)")
            urls = kv("urls.txt")
            for field, value in (("subtitle", read("subtitle.txt")), ("privacyPolicyUrl", urls["privacy"])):
                st2, r2 = patch("appInfoLocalizations", loc["id"], {field: value})
                out(f"  {field}: " + ("set" if st2 == 200 else f"FAILED (HTTP {st2}): {err(r2)}"))
                if st2 != 200:
                    PROBLEMS.append(f"{field} not set: {err(r2)}")

    # categories
    rel = info.get("relationships", {})
    st, res = call("GET", f"/v1/appInfos/{iid}/primaryCategory")
    cur = (res.get("data") or {}).get("id") if st == 200 else None
    out(f"  primary category now: {cur or 'none'}")
    if APPLY:
        cats = kv("categories.txt")
        st2, r2 = patch("appInfos", iid, relationships={
            "primaryCategory": {"data": {"type": "appCategories", "id": cats["primary"]}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": cats["secondary"]}}})
        out(f"  categories {cats['primary']} / {cats['secondary']}: " + ("set" if st2 == 200 else f"FAILED (HTTP {st2}): {err(r2)}"))
        if st2 != 200:
            PROBLEMS.append(f"categories not set: {err(r2)}")
    _ = rel

    # age rating
    st, res = call("GET", f"/v1/appInfos/{iid}/ageRatingDeclaration")
    decl = res.get("data") if st == 200 else None
    if not decl:
        out(f"  age rating declaration: not readable (HTTP {st})")
    else:
        attrs = decl.get("attributes", {})
        unanswered = [k for k, v in attrs.items() if v is None]
        out(f"  age rating declaration: {len(attrs)} questions, {len(unanswered)} unanswered")
        if APPLY:
            levels = {"alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes",
                      "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
                      "sexualContentGraphicAndNudity", "sexualContentOrNudity", "violenceCartoonOrFantasy",
                      "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic", "gunsOrOtherWeapons"}
            falses = {"gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat", "userGeneratedContent",
                      "advertising", "parentalControls", "ageAssurance", "seventeenPlus", "socialMedia",
                      "socialMediaAgeRestricted"}
            optional = {"developerAgeRatingInfoUrl", "gracRatingClassificationNumber", "kidsAgeBand",
                        "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride"}   # not a kids app; no override
            trues = {"healthOrWellnessTopics"}   # honest answer for a fitness-training app
            new = {}
            for k in attrs:
                if k in levels:
                    new[k] = "NONE"
                elif k in falses:
                    new[k] = False
                elif k in trues:
                    new[k] = True
            skipped = sorted(k for k in attrs if k not in new and k not in optional and attrs[k] is None)
            st2, r2 = patch("ageRatingDeclarations", decl["id"], new)
            out(f"  age rating: {len(new)} answers " + ("set" if st2 == 200 else f"FAILED (HTTP {st2}): {err(r2)}"))
            if st2 != 200:
                PROBLEMS.append(f"age rating not set: {err(r2)}")
            if skipped:
                problem("age rating questions left for the owner (unknown to this script): " + ", ".join(skipped))
    return iid


# ------------------------------------------------------------------------------------------------ version
def version(app_id):
    st, res = call("GET", f"/v1/apps/{app_id}/appStoreVersions", query={"filter[platform]": "IOS", "limit": 20})
    if st != 200:
        problem(f"could not read versions (HTTP {st}): {err(res)}")
        return None
    vers = res.get("data", [])
    for v in vers:
        a = v["attributes"]
        out(f"  version {a.get('versionString')}: {state_of(a, 'appVersionState', 'appStoreState')}")
    editable = [v for v in vers if state_of(v["attributes"], "appVersionState", "appStoreState") in EDITABLE_VERSION]
    if not editable:
        if not APPLY:
            out("  no editable version (apply mode creates 1.0.0)")
            return None
        st, res = call("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": TARGET_VERSION},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        if st not in (200, 201):
            problem(f"could not create version {TARGET_VERSION} (HTTP {st}): {err(res)}")
            return None
        out(f"  version {TARGET_VERSION}: created")
        v = res["data"]
    else:
        v = editable[0]
    vid = v["id"]
    a = v["attributes"]
    if APPLY:
        attrs = {"copyright": read("copyright.txt")}
        if a.get("versionString") != TARGET_VERSION:
            attrs["versionString"] = TARGET_VERSION   # the build's CFBundleShortVersionString is 1.0.0
        st2, r2 = patch("appStoreVersions", vid, attrs)
        out("  version " + ", ".join(f"{k}" for k in attrs) + ": " + ("set" if st2 == 200 else f"FAILED (HTTP {st2}): {err(r2)}"))
        if st2 != 200:
            PROBLEMS.append(f"version attributes not set: {err(r2)}")
    # attached build (read only)
    st, res = call("GET", f"/v1/appStoreVersions/{vid}/build")
    b = (res.get("data") or {}) if st == 200 else {}
    out("  build attached to the version: " + (f"{b['attributes'].get('version')} ({b['attributes'].get('processingState')})" if b else "none (the owner selects it before submission)"))
    return vid


def version_localization(vid, primary_locale):
    st, res = call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", query={"limit": 50})
    locs = res.get("data", []) if st == 200 else []
    loc = next((l for l in locs if l["attributes"].get("locale") == primary_locale), None) \
        or next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)
    urls = kv("urls.txt")
    fields = {"description": read("description.txt"), "keywords": read("keywords.txt"),
              "promotionalText": read("promotional_text.txt"), "supportUrl": urls["support"], "marketingUrl": urls["marketing"]}
    if loc is None:
        if not APPLY:
            out(f"  version localization {primary_locale}: missing")
            return None
        st, res = call("POST", "/v1/appStoreVersionLocalizations", {"data": {
            "type": "appStoreVersionLocalizations", "attributes": dict(fields, locale=primary_locale),
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        if st not in (200, 201):
            problem(f"could not create the version localization (HTTP {st}): {err(res)}")
            return None
        out(f"  version localization {primary_locale}: created with all fields")
        return res["data"]["id"]
    a = loc["attributes"]
    out(f"  version localization {a.get('locale')}: " + ", ".join(f"{k} {'set' if a.get(k) else 'empty'}" for k in fields))
    if APPLY:
        for k, v in fields.items():   # one PATCH per field so one rejection does not block the rest
            st2, r2 = patch("appStoreVersionLocalizations", loc["id"], {k: v})
            out(f"  {k}: " + ("set" if st2 == 200 else f"FAILED (HTTP {st2}): {err(r2)}"))
            if st2 != 200:
                PROBLEMS.append(f"{k} not set: {err(r2)}")
    return loc["id"]


def review_detail(vid):
    notes = read("review_notes.txt")
    st, res = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    d = res.get("data") if st == 200 else None
    contact = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")
    if d:
        a = d["attributes"]
        out("  review detail: notes " + ("set" if a.get("notes") else "empty") + "; contact fields: " +
            ", ".join(f"{k[7:]} {'set' if a.get(k) else 'empty'}" for k in contact))
    else:
        out("  review detail: none yet")
    if not APPLY:
        return
    attrs = {"notes": notes, "demoAccountRequired": False}
    if d and d["attributes"].get("notes") == notes and d["attributes"].get("demoAccountRequired") is False:
        out("  review notes + demo account not required: already set")
        return
    if d and not all(d["attributes"].get(k) for k in contact):
        # Apple only accepts an update once the owner has entered the contact fields in App Store Connect
        problem("review notes differ from ios/store/en-US/review_notes.txt but cannot be updated until the owner fills the App Review contact fields")
        return
    if d:
        st2, r2 = patch("appStoreReviewDetails", d["id"], attrs)
    else:
        st2, r2 = call("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    out("  review notes + demo account not required: " + ("set" if st2 in (200, 201) else f"FAILED (HTTP {st2}): {err(r2)}"))
    if st2 not in (200, 201):
        PROBLEMS.append(f"review notes not set: {err(r2)}")


# ------------------------------------------------------------------------------------------------ screenshots
def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def screenshots(loc_id):
    files = sorted(os.path.join(SHOT_DIR, f) for f in os.listdir(SHOT_DIR) if f.lower().endswith(".png")) if SHOT_DIR and os.path.isdir(SHOT_DIR) else []
    out(f"  screenshots taken by the simulator job: {len(files)}" + "".join(f"\n    {os.path.basename(f)} {png_size(f)}" for f in files))
    st, res = call("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", query={"limit": 50})
    sets = res.get("data", []) if st == 200 else []
    for s in sets:
        sid = s["id"]
        st3, r3 = call("GET", f"/v1/appScreenshotSets/{sid}/appScreenshots", query={"limit": 50})
        items = r3.get("data", []) if st3 == 200 else []
        states = [((i["attributes"].get("assetDeliveryState") or {}).get("state") or "?") for i in items]
        out(f"  screenshot set {s['attributes'].get('screenshotDisplayType')}: {len(items)} screenshot(s)" + (f" — {', '.join(states)}" if states else ""))
    if not APPLY or not files:
        return
    sizes = {png_size(f) for f in files}
    # The API has no separate 6.9" type: APP_IPHONE_67 is the largest iPhone set and accepts 1320x2868 (verified 26 Oct 2026).
    display = "APP_IPHONE_67" if sizes <= {(1290, 2796), (1284, 2778), (1320, 2868)} else "APP_IPHONE_69"
    target = next((s for s in sets if s["attributes"].get("screenshotDisplayType") in (display,)), None)
    if target is None:
        for dt in ([display, "APP_IPHONE_67"] if display == "APP_IPHONE_69" else [display]):
            st, res = call("POST", "/v1/appScreenshotSets", {"data": {
                "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": dt},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
            if st in (200, 201):
                target = res["data"]
                out(f"  screenshot set {dt}: created")
                break
            out(f"  screenshot set {dt}: not created (HTTP {st}): {err(res)}")
    if target is None:
        problem("no screenshot set could be created; upload the PNGs from ci-logs by hand")
        return
    sid = target["id"]
    st, res = call("GET", f"/v1/appScreenshotSets/{sid}/appScreenshots", query={"limit": 50})
    existing = res.get("data", []) if st == 200 else []
    keep = 0
    for s in existing:
        if (s["attributes"].get("fileName") or "").startswith((SHOT_PREFIX,) + OLD_SHOT_PREFIXES):
            st2, _ = call("DELETE", f"/v1/appScreenshots/{s['id']}")
            out(f"  removed earlier script screenshot: {'ok' if st2 in (200, 204) else st2}")
        else:
            keep += 1
    if keep:
        out(f"  {keep} screenshot(s) uploaded by someone else were kept")
    uploaded = 0
    for f in files[: max(0, 10 - keep)]:
        data = open(f, "rb").read()
        name = SHOT_PREFIX + os.path.basename(f)
        st, res = call("POST", "/v1/appScreenshots", {"data": {
            "type": "appScreenshots", "attributes": {"fileName": name, "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sid}}}}})
        if st not in (200, 201):
            problem(f"{name}: reservation failed (HTTP {st}): {err(res)}")
            continue
        shot = res["data"]
        ok = True
        for op in shot["attributes"].get("uploadOperations") or []:
            chunk = data[op["offset"]: op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
            for h in op.get("requestHeaders") or []:
                req.add_header(h["name"], h["value"])
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    r.read()
            except urllib.error.HTTPError as e:
                ok = False
                problem(f"{name}: upload part failed (HTTP {e.code})")
                break
        if not ok:
            continue
        st, res = patch("appScreenshots", shot["id"], {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()})
        if st == 200:
            uploaded += 1
        else:
            problem(f"{name}: commit failed (HTTP {st}): {err(res)}")
    out(f"  screenshots uploaded to {target['attributes'].get('screenshotDisplayType')}: {uploaded}/{len(files)} (Apple processes them in a few minutes)")


# ------------------------------------------------------------------------------------------------ read-only extras
def extras(app_id):
    st, res = call("GET", "/v1/builds", query={"filter[app]": app_id, "sort": "-uploadedDate", "limit": 3})
    for b in (res.get("data", []) if st == 200 else []):
        a = b["attributes"]
        out(f"  build {a.get('version')}: {a.get('processingState')}, uploaded {str(a.get('uploadedDate'))[:16]}")
    st, res = call("GET", f"/v1/apps/{app_id}/appPriceSchedule")
    out("  price schedule: " + ("exists (not changed by this script)" if st == 200 and res.get("data") else "not set — owner sets the price (Free) in App Store Connect › Pricing and Availability"))


def main():
    for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"):
        if not os.environ.get(k, "").strip():
            out(f"App Store Connect secret {k} missing — nothing done.")
            return 1
    asc.TOKEN = asc.token()
    out(f"Cyclift App Store listing — mode {MODE.upper()} (drafts only; never submits, releases, prices or accepts agreements)")
    out()
    sign_in_with_apple()
    out()
    app_id = asc.find_app()
    if not app_id:
        problem("App Store Connect app record not found")
        return finish()
    st, res = call("GET", f"/v1/apps/{app_id}")
    attrs = res.get("data", {}).get("attributes", {}) if st == 200 else {}
    primary = attrs.get("primaryLocale") or "en-US"
    out(f"App record: found; store name {shown_name(attrs.get('name'))}, primary language {primary}")
    out()
    out("App information:")
    app_info(app_id, primary)
    out()
    out("Version:")
    vid = version(app_id)
    if vid:
        out()
        out("Version text:")
        lid = version_localization(vid, primary)
        out()
        out("App Review:")
        review_detail(vid)
        if lid:
            out()
            out("Screenshots:")
            screenshots(lid)
    out()
    out("Builds and pricing (read only):")
    extras(app_id)
    return finish()


def finish():
    out()
    out("Problems: " + (str(len(PROBLEMS)) if PROBLEMS else "none"))
    for p in PROBLEMS:
        out("  - " + p)
    out()
    out("Not possible through the API (owner, in App Store Connect): App Privacy questionnaire, price (Free) and "
        "availability, App Review contact name/phone/e-mail, choosing the build, Submit for Review.")
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(LINES) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
