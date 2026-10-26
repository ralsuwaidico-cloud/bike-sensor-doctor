#!/usr/bin/env python3
"""App Store Connect preparation for Cyclift 1.0.0 — DRAFTS ONLY. Run by .github/workflows/asc-listing.yml.

It NEVER creates a review submission, submits for review, releases, accepts agreements or sets a paid price.

MODE=check        read-only: full report + submission-readiness checklist (OK / MISSING / OWNER).
MODE=apply        writes drafts, idempotently, then prints the checklist:
                    - app name (first accepted candidate), subtitle, privacy policy URL, categories, age rating answers
                    - content rights: DOES_NOT_USE_THIRD_PARTY_CONTENT
                    - version 1.0.0 (created only if no editable version exists), copyright, release type MANUAL
                    - description, keywords, promotional text, support + marketing URLs (lengths and wording verified)
                    - App Review notes, demo account not required (contact fields are never invented)
                    - price: Free (base territory USA unless one is already set)
                    - availability: every territory, available in new territories
MODE=attach       BUILD_NUMBER=<n>: waits until build <n> of 1.0.0 is VALID, answers export compliance
                  (usesNonExemptEncryption=false) if Apple still asks, attaches it to version 1.0.0.
MODE=screenshots  uploads $SCREENSHOT_DIR/*.png to the matching iPhone 6.9"/6.7" (and Apple Watch) sets, replacing
                  only screenshots this script uploaded earlier.

Inputs (environment): ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY (secrets), MODE, BUILD_NUMBER, SCREENSHOT_DIR,
REPORT (report path). The repository is public: the output never contains e-mail addresses, personal names, phone
numbers, team IDs or key material (contact fields are reported only as "set"/"empty").
"""
import hashlib
import os
import re
import struct
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402  (token(), call(), errors_text(), find_app())

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
STORE = os.path.join(ROOT, "store", "en-US")
MODE = os.environ.get("MODE", "check").strip().lower()
WRITE = MODE == "apply"
BUILD_NUMBER = os.environ.get("BUILD_NUMBER", "").strip()
SHOT_DIR = os.environ.get("SCREENSHOT_DIR", "").strip()
REPORT = os.environ.get("REPORT", "asc-listing-report.txt")
WAIT_MINUTES = int(os.environ.get("WAIT_MINUTES", "75") or 75)
SHOT_PREFIX = "cyclift-store-"
OLD_SHOT_PREFIXES = ("athletics-store-",)   # earlier uploads by this script (pre-rename) are replaced too
TARGET_VERSION = "1.0.0"
BASE_TERRITORY = "USA"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}

# App Store limits (characters)
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170, "description": 4000, "notes": 4000}
# Never in the 1.0 listing (decisions doc: no accounts/sync, no Garmin/WHOOP/Oura, no placeholders; no AI, medical
# or competitor claims). Matched case-insensitively on word boundaries.
FORBIDDEN = [r"sign[ -]?in with", r"\bsync", r"log ?in\b", r"garmin", r"whoop", r"\boura\b", r"coming soon",
             r"\bplanned for\b", r"\bsoon\b", r"\bAI\b", r"artificial intelligence", r"machine learning", r"\bGPT",
             r"strava", r"zwift", r"wahoo", r"trainingpeaks", r"peloton", r"\bcures?\b", r"\bdiagnos", r"\btreat(s|ment)\b",
             r"\bheal(s|ing)?\b"]

EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
PHONE = re.compile(r"\+?\d[\d ()-]{7,}\d")
LINES, PROBLEMS = [], []
STATE = {}   # facts collected for the readiness checklist


def scrub(msg):
    return EMAIL.sub("<e-mail hidden>", str(msg))


def out(msg=""):
    msg = scrub(msg)
    LINES.append(msg)
    print(msg, flush=True)


def problem(msg):
    PROBLEMS.append(scrub(msg))
    out("  ! " + msg)


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
    return PHONE.sub("<number hidden>", scrub(asc.errors_text(res)))


def call(method, path, body=None, query=None):
    return asc.call(method, path, body, query)


def patch(kind, ident, attributes=None, relationships=None):
    data = {"type": kind, "id": ident}
    if attributes:
        data["attributes"] = attributes
    if relationships:
        data["relationships"] = relationships
    return call("PATCH", f"/v1/{kind}/{ident}", {"data": data})


def get_all(path, query=None, cap=1000):
    """GET a collection, following links.next. Returns (status, data list, included list)."""
    q = dict(query or {})
    q.setdefault("limit", 200)
    st, res = call("GET", path, query=q)
    if st != 200:
        return st, [], [], res
    data, inc = list(res.get("data", [])), list(res.get("included", []))
    nxt = (res.get("links") or {}).get("next")
    while nxt and len(data) < cap:
        rel = nxt.replace(asc.API, "")
        st2, r2 = call("GET", rel)
        if st2 != 200:
            break
        data += r2.get("data", [])
        inc += r2.get("included", [])
        nxt = (r2.get("links") or {}).get("next")
    return st, data, inc, res


def state_of(attrs, *keys):
    for k in keys:
        if attrs.get(k):
            return attrs[k]
    return "?"


def shown_name(n):
    """The current store name may contain the owner's personal name: show it only when it is one of our candidates."""
    try:
        cands = [c.strip() for c in read("name_candidates.txt").splitlines() if c.strip()]
    except OSError:
        cands = []
    return f"'{n}'" if n in cands else f"(not a Cyclift candidate, {len(n or '')} characters — hidden)"


# ------------------------------------------------------------------------------------------------ local text checks
def text_ok(field, value, forbid=True):
    """Length + wording gate. Returns False (and records a problem) when the text must not be sent."""
    ok = True
    lim = LIMITS.get(field)
    if lim and len(value) > lim:
        problem(f"{field}: {len(value)} characters > limit {lim} — not written")
        ok = False
    if forbid:
        hits = sorted({m.group(0) for p in FORBIDDEN for m in re.finditer(p, value, re.IGNORECASE)})
        if hits:
            problem(f"{field}: contains words not allowed in the 1.0 listing ({', '.join(hits)}) — not written")
            ok = False
    return ok


def local_texts():
    out("Listing texts in ios/store/en-US (local checks):")
    urls = kv("urls.txt")
    texts = {"subtitle": read("subtitle.txt"), "keywords": read("keywords.txt"),
             "promotionalText": read("promotional_text.txt"), "description": read("description.txt")}
    for k, v in texts.items():
        lim = LIMITS[k]
        good = text_ok(k, v)
        out(f"  {k}: {len(v)}/{lim} characters, wording {'OK' if good else 'BLOCKED'}")
    kw = texts["keywords"].split(",")
    if any(not w.strip() or w != w.strip() for w in kw):
        problem("keywords: empty entries or spaces around commas")
    notes = read("review_notes.txt")
    text_ok("notes", notes, forbid=False)
    out(f"  review notes: {len(notes)}/{LIMITS['notes']} characters")
    out("Listing URLs (fetched from this runner):")
    STATE["urls"] = {}
    for k in ("marketing", "support", "privacy", "terms"):
        u = urls.get(k)
        if not u:
            continue
        try:
            req = urllib.request.Request(u, headers={"User-Agent": "cyclift-asc-check"})
            with urllib.request.urlopen(req, timeout=20) as r:
                code, body = r.status, r.read(200000).decode("utf-8", "replace")
            title = re.search(r"<title>(.*?)</title>", body, re.S | re.I)
            note = f"HTTP {code}, title '{(title.group(1).strip() if title else '?')[:60]}'"
            if re.search(r"SUPPORT_EMAIL|TODO|placeholder", body):
                note += " — contains a placeholder"
            STATE["urls"][k] = code == 200
        except urllib.error.HTTPError as e:
            note = f"HTTP {e.code} (not published yet?)"
            STATE["urls"][k] = False
        except Exception as e:   # noqa: BLE001
            note = f"not reachable ({type(e).__name__})"
            STATE["urls"][k] = False
        out(f"  {k}: {u} — {note}")


# ------------------------------------------------------------------------------------------------ app level
def app_level(app_id, attrs):
    cr = attrs.get("contentRightsDeclaration")
    out(f"  content rights: {cr or 'not answered'}")
    if WRITE and cr != "DOES_NOT_USE_THIRD_PARTY_CONTENT":
        st, res = patch("apps", app_id, {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"})
        out("  content rights -> DOES_NOT_USE_THIRD_PARTY_CONTENT: " + ("set" if st == 200 else f"FAILED (HTTP {st}): {err(res)}"))
        if st == 200:
            cr = "DOES_NOT_USE_THIRD_PARTY_CONTENT"
        else:
            PROBLEMS.append(f"content rights not set: {err(res)}")
    STATE["content_rights"] = cr == "DOES_NOT_USE_THIRD_PARTY_CONTENT"
    st, res = call("GET", "/v1/bundleIds", query={"filter[identifier]": asc.APP_BUNDLE, "limit": 50})
    match = [b for b in res.get("data", []) if b["attributes"]["identifier"] == asc.APP_BUNDLE] if st == 200 else []
    if match:
        st, res = call("GET", f"/v1/bundleIds/{match[0]['id']}/bundleIdCapabilities")
        caps = sorted({c["attributes"]["capabilityType"] for c in res.get("data", [])}) if st == 200 else []
        out("  bundle ID capabilities (read only): " + (", ".join(caps) or "none"))


# ------------------------------------------------------------------------------------------------ app info
AGE_LEVELS = {"alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes",
              "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
              "sexualContentGraphicAndNudity", "sexualContentOrNudity", "violenceCartoonOrFantasy",
              "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic", "gunsOrOtherWeapons"}
AGE_FALSE = {"gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat", "userGeneratedContent",
             "advertising", "parentalControls", "ageAssurance", "seventeenPlus", "socialMedia", "socialMediaAgeRestricted"}
AGE_TRUE = {"healthOrWellnessTopics"}   # honest answer for a fitness-training app
AGE_OPTIONAL = {"developerAgeRatingInfoUrl", "gracRatingClassificationNumber", "kidsAgeBand", "ageRatingOverride",
                "ageRatingOverrideV2", "koreaAgeRatingOverride"}   # not a kids app; no override


def app_info(app_id, primary_locale):
    st, res = call("GET", f"/v1/apps/{app_id}/appInfos", query={"limit": 10})
    if st != 200:
        problem(f"could not read app infos (HTTP {st}): {err(res)}")
        return None
    infos = res.get("data", [])
    for i in infos:
        a = i["attributes"]
        ratings = {k: v for k, v in a.items() if "rating" in k.lower() and v}
        out(f"  app info {i['id'][:8]}…: state {state_of(a, 'state', 'appStoreState')}"
            + (" — computed rating: " + ", ".join(f"{k}={v}" for k, v in sorted(ratings.items())) if ratings else ""))
        if ratings:
            STATE["computed_rating"] = ratings.get("appStoreAgeRating") or next(iter(ratings.values()))
    editable = [i for i in infos if state_of(i["attributes"], "state", "appStoreState") in EDITABLE]
    if not editable:
        problem("no editable app info (the app name/category are locked while a version is in review or live)")
        return None
    iid = editable[0]["id"]

    # localization (name, subtitle, privacy URL)
    st, res = call("GET", f"/v1/appInfos/{iid}/appInfoLocalizations", query={"limit": 50})
    locs = res.get("data", []) if st == 200 else []
    loc = next((l for l in locs if l["attributes"].get("locale") == primary_locale), None) \
        or next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)
    if loc is None:
        problem(f"no app info localization for {primary_locale}")
    else:
        a = loc["attributes"]
        urls = kv("urls.txt")
        want = {"subtitle": read("subtitle.txt"), "privacyPolicyUrl": urls["privacy"]}
        out(f"  locale {a.get('locale')}: name {shown_name(a.get('name'))}, subtitle "
            f"{'matches' if a.get('subtitle') == want['subtitle'] else 'differs/empty'}, privacy URL "
            f"{'matches' if a.get('privacyPolicyUrl') == want['privacyPolicyUrl'] else 'differs/empty'}")
        names = [n.strip() for n in read("name_candidates.txt").splitlines() if n.strip()]
        STATE["name"] = a.get("name") in names
        if WRITE and not STATE["name"]:
            for n in names:
                if len(n) > LIMITS["name"]:
                    continue
                st2, r2 = patch("appInfoLocalizations", loc["id"], {"name": n})
                out(f"  name '{n}': " + ("ACCEPTED" if st2 == 200 else f"rejected (HTTP {st2}): {err(r2)}"))
                if st2 == 200:
                    STATE["name"] = True
                    break
            if not STATE["name"]:
                problem("none of the name candidates was accepted")
        for field, value in want.items():
            have = a.get(field) == value
            if WRITE and not have and text_ok(field if field in LIMITS else "", value, forbid=field == "subtitle"):
                st2, r2 = patch("appInfoLocalizations", loc["id"], {field: value})
                out(f"  {field}: " + ("set" if st2 == 200 else f"FAILED (HTTP {st2}): {err(r2)}"))
                have = st2 == 200
                if not have:
                    PROBLEMS.append(f"{field} not set: {err(r2)}")
            STATE[field] = have

    # categories
    cats = kv("categories.txt")
    st, res = call("GET", f"/v1/appInfos/{iid}/primaryCategory")
    p = (res.get("data") or {}).get("id") if st == 200 else None
    st, res = call("GET", f"/v1/appInfos/{iid}/secondaryCategory")
    s = (res.get("data") or {}).get("id") if st == 200 else None
    out(f"  categories now: {p or 'none'} / {s or 'none'}")
    if WRITE and (p, s) != (cats["primary"], cats["secondary"]):
        st2, r2 = patch("appInfos", iid, relationships={
            "primaryCategory": {"data": {"type": "appCategories", "id": cats["primary"]}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": cats["secondary"]}}})
        out(f"  categories {cats['primary']} / {cats['secondary']}: " + ("set" if st2 == 200 else f"FAILED (HTTP {st2}): {err(r2)}"))
        if st2 == 200:
            p = cats["primary"]
        else:
            PROBLEMS.append(f"categories not set: {err(r2)}")
    STATE["category"] = p == cats["primary"]

    # age rating
    st, res = call("GET", f"/v1/appInfos/{iid}/ageRatingDeclaration")
    decl = res.get("data") if st == 200 else None
    if not decl:
        out(f"  age rating declaration: not readable (HTTP {st})")
        STATE["age"] = False
        return iid
    attrs = decl.get("attributes", {})
    want = {k: ("NONE" if k in AGE_LEVELS else (False if k in AGE_FALSE else True))
            for k in attrs if k in AGE_LEVELS | AGE_FALSE | AGE_TRUE}
    unknown = sorted(k for k in attrs if k not in want and k not in AGE_OPTIONAL and attrs[k] is None)
    diff = sorted(k for k, v in want.items() if attrs.get(k) != v)
    not_none = sorted(f"{k}={v}" for k, v in attrs.items() if k in AGE_LEVELS and v not in (None, "NONE"))
    yes = sorted(k for k, v in attrs.items() if v is True)
    out(f"  age rating declaration: {len(attrs)} questions; {len(want) - len(diff)}/{len(want)} answered as intended; "
        f"content levels other than NONE: {', '.join(not_none) or 'none'}; 'yes' answers: {', '.join(yes) or 'none'}"
        f"; optional left empty: {', '.join(sorted(k for k in AGE_OPTIONAL if k in attrs and attrs[k] is None)) or 'none'}")
    if WRITE and diff:
        st2, r2 = patch("ageRatingDeclarations", decl["id"], {k: want[k] for k in diff})
        out(f"  age rating: {len(diff)} answers " + ("set" if st2 == 200 else f"FAILED (HTTP {st2}): {err(r2)}"))
        if st2 == 200:
            diff = []
        else:
            PROBLEMS.append(f"age rating not set: {err(r2)}")
    if unknown:
        problem("age rating questions unknown to this script (owner answers them): " + ", ".join(unknown))
    STATE["age"] = not diff and not unknown
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
        out(f"  version {a.get('versionString')}: {state_of(a, 'appVersionState', 'appStoreState')}, "
            f"release type {a.get('releaseType') or 'not set'}, copyright {'set' if a.get('copyright') else 'empty'}")
    editable = [v for v in vers if state_of(v["attributes"], "appVersionState", "appStoreState") in EDITABLE]
    if not editable:
        if not WRITE:
            out("  no editable version (apply mode creates 1.0.0)")
            return None
        st, res = call("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": TARGET_VERSION, "releaseType": "MANUAL"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        if st not in (200, 201):
            problem(f"could not create version {TARGET_VERSION} (HTTP {st}): {err(res)}")
            return None
        out(f"  version {TARGET_VERSION}: created")
        v = res["data"]
    else:
        v = editable[0]
    vid, a = v["id"], v["attributes"]
    STATE["version_state"] = state_of(a, "appVersionState", "appStoreState")
    want = {"copyright": read("copyright.txt"), "releaseType": "MANUAL", "versionString": TARGET_VERSION}
    diff = {k: val for k, val in want.items() if a.get(k) != val}
    if WRITE and diff:
        if "releaseType" in diff:
            diff["earliestReleaseDate"] = None   # MANUAL must not carry a scheduled date
        st2, r2 = patch("appStoreVersions", vid, diff)
        out("  version " + ", ".join(f"{k}={'(cleared)' if val is None else val}" for k, val in diff.items()) + ": "
            + ("set" if st2 == 200 else f"FAILED (HTTP {st2}): {err(r2)}"))
        if st2 == 200:
            a = dict(a, **{k: val for k, val in diff.items()})
        else:
            PROBLEMS.append(f"version attributes not set: {err(r2)}")
    STATE["copyright"] = a.get("copyright") == want["copyright"]
    STATE["release_type"] = a.get("releaseType")
    STATE["version_ok"] = a.get("versionString") == TARGET_VERSION
    st, res = call("GET", f"/v1/appStoreVersions/{vid}/build")
    b = (res.get("data") or {}) if st == 200 else {}
    if b:
        ba = b["attributes"]
        STATE["build"] = f"{ba.get('version')} ({ba.get('processingState')})"
        STATE["build_ok"] = ba.get("processingState") == "VALID"
        STATE["build_encryption"] = ba.get("usesNonExemptEncryption")
    out("  build attached: " + (STATE.get("build") or "none"))
    return vid


def version_localization(vid, primary_locale):
    st, res = call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", query={"limit": 50})
    locs = res.get("data", []) if st == 200 else []
    loc = next((l for l in locs if l["attributes"].get("locale") == primary_locale), None) \
        or next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)
    urls = kv("urls.txt")
    fields = {"description": read("description.txt"), "keywords": read("keywords.txt"),
              "promotionalText": read("promotional_text.txt"), "supportUrl": urls["support"],
              "marketingUrl": urls["marketing"]}
    if loc is None:
        if not WRITE:
            out(f"  version localization {primary_locale}: missing")
            return None
        good = {k: v for k, v in fields.items() if k not in LIMITS or text_ok(k, v)}
        st, res = call("POST", "/v1/appStoreVersionLocalizations", {"data": {
            "type": "appStoreVersionLocalizations", "attributes": dict(good, locale=primary_locale),
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        if st not in (200, 201):
            problem(f"could not create the version localization (HTTP {st}): {err(res)}")
            return None
        out(f"  version localization {primary_locale}: created")
        loc = res["data"]
    a = dict(loc["attributes"])
    out(f"  version localization {a.get('locale')}: " + ", ".join(
        f"{k} {'matches' if a.get(k) == v else ('differs' if a.get(k) else 'EMPTY')}" for k, v in fields.items())
        + f"; whatsNew {'set' if a.get('whatsNew') else 'empty (not used for a first version)'}")
    if WRITE:
        for k, v in fields.items():   # one PATCH per field so one rejection does not block the rest
            if a.get(k) == v or (k in LIMITS and not text_ok(k, v)):
                continue
            st2, r2 = patch("appStoreVersionLocalizations", loc["id"], {k: v})
            out(f"  {k}: " + ("set" if st2 == 200 else f"FAILED (HTTP {st2}): {err(r2)}"))
            if st2 == 200:
                a[k] = v
            else:
                PROBLEMS.append(f"{k} not set: {err(r2)}")
    for k, v in fields.items():
        STATE["loc_" + k] = a.get(k) == v
    STATE["loc_any"] = {k: bool(a.get(k)) for k in fields}
    return loc["id"]


CONTACT = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")


def review_detail(vid):
    notes = read("review_notes.txt")
    st, res = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    d = res.get("data") if st == 200 else None
    if d:
        a = d["attributes"]
        out("  review detail: notes " + ("match review_notes.txt" if a.get("notes") == notes else ("differ" if a.get("notes") else "empty"))
            + f"; demo account required: {a.get('demoAccountRequired')}; contact fields: "
            + ", ".join(f"{k[7:]} {'set' if a.get(k) else 'empty'}" for k in CONTACT))
        STATE["contact"] = all(a.get(k) for k in CONTACT)
        STATE["notes"] = a.get("notes") == notes
    else:
        out(f"  review detail: none yet (HTTP {st})")
        STATE["contact"], STATE["notes"] = False, False
    if not WRITE or STATE["notes"] and d and d["attributes"].get("demoAccountRequired") is False:
        return
    attrs = {"notes": notes, "demoAccountRequired": False}
    if d:
        st2, r2 = patch("appStoreReviewDetails", d["id"], attrs)
    else:
        st2, r2 = call("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    if st2 in (200, 201):
        out("  review notes + demo account not required: set")
        STATE["notes"] = True
    else:
        problem(f"review notes not accepted by Apple (HTTP {st2}): {err(r2)}"
                + (" — OWNER: fill App Review contact name/phone/e-mail in App Store Connect, then re-run apply"
                   if not STATE["contact"] else ""))


# ------------------------------------------------------------------------------------------------ price + availability
FREE = ("0", "0.0", "0.00")


def pricing(app_id):
    st, res = call("GET", f"/v1/apps/{app_id}/appPriceSchedule")
    sched = res.get("data") if st == 200 else None
    base, free_now, prices = None, False, []
    if sched:
        sid = sched["id"]
        st, r = call("GET", f"/v1/appPriceSchedules/{sid}/baseTerritory")
        base = (r.get("data") or {}).get("id") if st == 200 else None
        st, data, inc, r = get_all(f"/v1/appPriceSchedules/{sid}/manualPrices",
                                   {"include": "appPricePoint,territory", "limit": 50})
        pts = {i["id"]: i["attributes"].get("customerPrice") for i in inc if i["type"] == "appPricePoints"}
        for p in data:
            pp = ((p.get("relationships") or {}).get("appPricePoint") or {}).get("data") or {}
            tr = ((p.get("relationships") or {}).get("territory") or {}).get("data") or {}
            prices.append((tr.get("id"), pts.get(pp.get("id")), p["attributes"].get("startDate"), p["attributes"].get("endDate")))
        if st != 200:
            out(f"  manual prices: not readable (HTTP {st}): {err(r)}")
        current = [p for p in prices if not p[3]]
        free_now = bool(current) and all(str(p[1]) in FREE for p in current)
        out(f"  price schedule: base territory {base or '?'}; manual prices: "
            + (", ".join(f"{t or '?'} {c if c is not None else '?'}" + (f" from {s}" if s else "") for t, c, s, e in prices) or "none"))
    else:
        out(f"  price schedule: none (HTTP {st})")
    if WRITE and not free_now:
        terr = base or BASE_TERRITORY
        st, data, _, r = get_all(f"/v1/apps/{app_id}/appPricePoints", {"filter[territory]": terr, "limit": 200}, cap=200)
        free_pt = next((p for p in data if str(p["attributes"].get("customerPrice")) in FREE), None)
        if not free_pt:
            problem(f"free price point for {terr} not found (HTTP {st}): {err(r) if st != 200 else 'no 0.00 point'}")
        else:
            st2, r2 = call("POST", "/v1/appPriceSchedules", {
                "data": {"type": "appPriceSchedules", "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                    "baseTerritory": {"data": {"type": "territories", "id": terr}},
                    "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
                "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                              "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free_pt["id"]}}}}]})
            out(f"  price -> Free (base {terr}): " + ("set" if st2 in (200, 201) else f"FAILED (HTTP {st2}): {err(r2)}"))
            if st2 in (200, 201):
                free_now = True
            else:
                PROBLEMS.append(f"price not set to Free: {err(r2)}")
    STATE["price_free"] = free_now


def availability(app_id):
    st, res = call("GET", f"/v1/apps/{app_id}/appAvailabilityV2")
    av = res.get("data") if st == 200 else None
    st_t, all_terr, _, rt = get_all("/v1/territories", {"limit": 200})
    all_ids = [t["id"] for t in all_terr]
    if st_t != 200:
        problem(f"could not list territories (HTTP {st_t}): {err(rt)}")
    if av:
        new_terr = av["attributes"].get("availableInNewTerritories")
        st2, tas, inc, r2 = get_all(f"/v2/appAvailabilities/{av['id']}/territoryAvailabilities",
                                    {"include": "territory", "limit": 200})
        if st2 != 200:
            out(f"  territory availabilities not readable (HTTP {st2}): {err(r2)}")
        on = [t for t in tas if t["attributes"].get("available")]
        off = [t for t in tas if not t["attributes"].get("available")]
        out(f"  availability: {len(on)} of {len(tas)} territories available (Apple lists {len(all_ids)}), "
            f"available in new territories: {new_terr}")
        states = sorted({str(t["attributes"].get("contentStatuses") or "") for t in tas} - {""})
        if states:
            out("  territory content statuses: " + "; ".join(states)[:400])
        if WRITE and off:
            fixed = 0
            for t in off:
                st3, r3 = patch("territoryAvailabilities", t["id"], {"available": True})
                if st3 == 200:
                    fixed += 1
                elif fixed == 0:
                    out(f"  territory -> available: FAILED (HTTP {st3}): {err(r3)}")
            out(f"  territories switched on now: {fixed}/{len(off)}")
            on += off[:fixed]
            off = off[fixed:]
        if WRITE and new_terr is False:
            # v2 has no PATCH for this flag: re-POST the availability with every territory (Apple replaces it)
            new_terr = post_availability(app_id, all_ids, existing=True)
        STATE["availability"] = (len(on), len(tas) or len(all_ids), new_terr)
        STATE["avail_ok"] = bool(on) and not off and new_terr is True
    else:
        out(f"  availability: not set yet (HTTP {st})")
        STATE["availability"] = (0, len(all_ids), None)
        STATE["avail_ok"] = False
        if WRITE and all_ids:
            if post_availability(app_id, all_ids) is True:
                STATE["availability"] = (len(all_ids), len(all_ids), True)
                STATE["avail_ok"] = True


def post_availability(app_id, ids, existing=False):
    inc = [{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True},
            "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for t in ids]
    st, res = call("POST", "/v2/appAvailabilities", {
        "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                                   "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": i["id"]} for i in inc]}}},
        "included": inc})
    ok = st in (200, 201)
    out(f"  availability -> all {len(ids)} territories, new territories on: "
        + ("set" if ok else f"FAILED (HTTP {st}): {err(res)}"))
    if not ok:
        if existing:
            problem("'available in new territories' is off and the API would not change it — OWNER: Pricing and "
                    "Availability › Availability › tick 'make available in new territories'")
        else:
            PROBLEMS.append(f"availability not set: {err(res)}")
        return None
    return True


# ------------------------------------------------------------------------------------------------ screenshots
DISPLAY_BY_SIZE = {
    (1320, 2868): "APP_IPHONE_67", (1290, 2796): "APP_IPHONE_67", (1284, 2778): "APP_IPHONE_65", (1242, 2688): "APP_IPHONE_65",
    (422, 514): "APP_WATCH_ULTRA", (410, 502): "APP_WATCH_ULTRA",
    (416, 496): "APP_WATCH_SERIES_10", (374, 446): "APP_WATCH_SERIES_10",
    (396, 484): "APP_WATCH_SERIES_7", (352, 430): "APP_WATCH_SERIES_7",
}
IPHONE_SETS = ("APP_IPHONE_67", "APP_IPHONE_69", "APP_IPHONE_65")
WATCH_SETS = ("APP_WATCH_ULTRA", "APP_WATCH_SERIES_10", "APP_WATCH_SERIES_7", "APP_WATCH_SERIES_4", "APP_WATCH_SERIES_3")


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def screenshot_sets(loc_id):
    st, res = call("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", query={"limit": 50})
    sets = res.get("data", []) if st == 200 else []
    summary = {}
    for s in sets:
        st3, r3 = call("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots", query={"limit": 50})
        items = r3.get("data", []) if st3 == 200 else []
        states = [((i["attributes"].get("assetDeliveryState") or {}).get("state") or "?") for i in items]
        dt = s["attributes"].get("screenshotDisplayType")
        summary[dt] = (s, items, states)
        out(f"  set {dt}: {len(items)} screenshot(s)" + (f" — {', '.join(states)}" if states else ""))
    complete = lambda names: sum(states.count("COMPLETE") for dt, (_, _, states) in summary.items() if dt in names)  # noqa: E731
    STATE["shots_iphone"] = complete(IPHONE_SETS)
    STATE["shots_watch"] = complete(WATCH_SETS)
    return summary


def upload_screenshots(loc_id, summary):
    files = sorted(os.path.join(SHOT_DIR, f) for f in os.listdir(SHOT_DIR) if f.lower().endswith(".png")) \
        if SHOT_DIR and os.path.isdir(SHOT_DIR) else []
    out(f"  screenshots received from the simulator job: {len(files)}"
        + "".join(f"\n    {os.path.basename(f)} {png_size(f)}" for f in files))
    groups = {}
    for f in files:
        dt = DISPLAY_BY_SIZE.get(png_size(f))
        if dt is None:
            problem(f"{os.path.basename(f)}: size {png_size(f)} matches no App Store screenshot type — skipped")
            continue
        groups.setdefault(dt, []).append(f)
    if not groups:
        problem("no usable screenshots to upload")
        return
    for dt, group in groups.items():
        target = summary.get(dt, (None,))[0]
        if target is None:
            st, res = call("POST", "/v1/appScreenshotSets", {"data": {
                "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": dt},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
            if st not in (200, 201):
                problem(f"screenshot set {dt} not created (HTTP {st}): {err(res)}")
                continue
            target = res["data"]
            out(f"  set {dt}: created")
        sid = target["id"]
        st, res = call("GET", f"/v1/appScreenshotSets/{sid}/appScreenshots", query={"limit": 50})
        keep = 0
        for s in (res.get("data", []) if st == 200 else []):
            if (s["attributes"].get("fileName") or "").startswith((SHOT_PREFIX,) + OLD_SHOT_PREFIXES):
                st2, _ = call("DELETE", f"/v1/appScreenshots/{s['id']}")
                out(f"  {dt}: removed earlier script screenshot: {'ok' if st2 in (200, 204) else st2}")
            else:
                keep += 1
        if keep:
            out(f"  {dt}: {keep} screenshot(s) uploaded by someone else were kept")
        uploaded = 0
        for f in group[: max(0, 10 - keep)]:
            uploaded += upload_one(sid, f)
        out(f"  {dt}: uploaded {uploaded}/{len(group)} (Apple processes them in a few minutes)")


def upload_one(sid, path):
    data = open(path, "rb").read()
    name = SHOT_PREFIX + os.path.basename(path)
    st, res = call("POST", "/v1/appScreenshots", {"data": {
        "type": "appScreenshots", "attributes": {"fileName": name, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sid}}}}})
    if st not in (200, 201):
        problem(f"{name}: reservation failed (HTTP {st}): {err(res)}")
        return 0
    shot = res["data"]
    for op in shot["attributes"].get("uploadOperations") or []:
        req = urllib.request.Request(op["url"], data=data[op["offset"]: op["offset"] + op["length"]], method=op["method"])
        for h in op.get("requestHeaders") or []:
            req.add_header(h["name"], h["value"])
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                r.read()
        except urllib.error.HTTPError as e:
            problem(f"{name}: upload part failed (HTTP {e.code})")
            return 0
    st, res = patch("appScreenshots", shot["id"], {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()})
    if st != 200:
        problem(f"{name}: commit failed (HTTP {st}): {err(res)}")
        return 0
    return 1


# ------------------------------------------------------------------------------------------------ build attachment
def attach(app_id, vid):
    if not re.fullmatch(r"\d+", BUILD_NUMBER):
        problem("attach mode needs BUILD_NUMBER (the CFBundleVersion of the 1.0.0 build, e.g. 57)")
        return
    out(f"  waiting for build {BUILD_NUMBER} of {TARGET_VERSION} to be VALID (up to {WAIT_MINUTES} min)")
    deadline = time.time() + WAIT_MINUTES * 60
    build = None
    while True:
        st, res = call("GET", "/v1/builds", query={"filter[app]": app_id, "filter[version]": BUILD_NUMBER,
                                                  "filter[preReleaseVersion.version]": TARGET_VERSION, "limit": 5})
        data = res.get("data", []) if st == 200 else []
        build = data[0] if data else None
        ps = build["attributes"].get("processingState") if build else None
        if ps == "VALID":
            break
        if ps in ("FAILED", "INVALID"):
            problem(f"build {BUILD_NUMBER} processing state {ps} — cannot be attached")
            return
        if time.time() > deadline:
            problem(f"build {BUILD_NUMBER}: " + (f"still {ps}" if build else "not found in App Store Connect") + f" after {WAIT_MINUTES} min")
            return
        out(f"    build {BUILD_NUMBER}: {ps or 'not visible yet'} — waiting 60 s")
        time.sleep(60)
        asc.TOKEN = asc.token()   # tokens live 15 minutes
    a = build["attributes"]
    out(f"  build {BUILD_NUMBER}: VALID, expired {a.get('expired')}, usesNonExemptEncryption {a.get('usesNonExemptEncryption')}")
    if a.get("expired"):
        problem(f"build {BUILD_NUMBER} has expired")
        return
    if a.get("usesNonExemptEncryption") is None:
        st, res = patch("builds", build["id"], {"usesNonExemptEncryption": False})
        out("  export compliance (usesNonExemptEncryption=false): " + ("set" if st == 200 else f"FAILED (HTTP {st}): {err(res)}"))
        if st != 200:
            PROBLEMS.append(f"export compliance not answered: {err(res)}")
    st, res = call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
    out(f"  attach build {BUILD_NUMBER} to version {TARGET_VERSION}: " + ("done" if st in (200, 204) else f"FAILED (HTTP {st}): {err(res)}"))
    if st not in (200, 204):
        PROBLEMS.append(f"build not attached: {err(res)}")


# ------------------------------------------------------------------------------------------------ read-only extras
def extras(app_id):
    st, res = call("GET", "/v1/builds", query={"filter[app]": app_id, "sort": "-uploadedDate", "limit": 5,
                                              "include": "preReleaseVersion"})
    pre = {i["id"]: i["attributes"].get("version") for i in res.get("included", []) if i["type"] == "preReleaseVersions"} if st == 200 else {}
    for b in (res.get("data", []) if st == 200 else []):
        a = b["attributes"]
        pv = pre.get(((b.get("relationships") or {}).get("preReleaseVersion") or {}).get("data", {}).get("id"))
        out(f"  build {a.get('version')} ({pv or '?'}): {a.get('processingState')}, uploaded {str(a.get('uploadedDate'))[:16]}, "
            f"encryption answer {a.get('usesNonExemptEncryption')}, expired {a.get('expired')}")
    # read only: there must be no review submission (this script never creates one)
    st, res = call("GET", "/v1/reviewSubmissions", query={"filter[app]": app_id, "limit": 10})
    subs = res.get("data", []) if st == 200 else []
    STATE["submissions"] = [s["attributes"].get("state") for s in subs]
    out("  review submissions: " + (", ".join(str(s) for s in STATE["submissions"]) if subs else "none") + (f" (HTTP {st})" if st != 200 else ""))


# ------------------------------------------------------------------------------------------------ readiness
def readiness():
    s = STATE
    rows = []

    def row(item, ok, detail=""):
        rows.append((item, ok, detail))

    la = s.get("loc_any", {})
    row("App name", "OK" if s.get("name") else "MISSING")
    row("Subtitle", "OK" if s.get("subtitle") else "MISSING")
    row("Privacy policy URL (set in ASC)", "OK" if s.get("privacyPolicyUrl") else "MISSING")
    for k, label in (("privacy", "Privacy page online"), ("support", "Support page online"), ("marketing", "Marketing page online")):
        if k in s.get("urls", {}):
            row(label, "OK" if s["urls"][k] else "OWNER", "" if s["urls"][k] else "publish GitHub Pages (see APP_STORE_SUBMISSION.md)")
    row("Support URL (set in ASC)", "OK" if s.get("loc_supportUrl") else ("DIFFERS" if la.get("supportUrl") else "MISSING"))
    row("Description", "OK" if s.get("loc_description") else ("DIFFERS" if la.get("description") else "MISSING"))
    row("Keywords", "OK" if s.get("loc_keywords") else ("DIFFERS" if la.get("keywords") else "MISSING"))
    row("Promotional text (optional)", "OK" if s.get("loc_promotionalText") else "DIFFERS")
    row("Category Health & Fitness / Sports", "OK" if s.get("category") else "MISSING")
    row("Copyright", "OK" if s.get("copyright") else "MISSING")
    row("Version string 1.0.0", "OK" if s.get("version_ok") else "MISSING", s.get("version_state", ""))
    row("Release type MANUAL", "OK" if s.get("release_type") == "MANUAL" else "MISSING", s.get("release_type") or "")
    row("Age rating questionnaire", "OK" if s.get("age") else "MISSING", f"computed {s.get('computed_rating')}" if s.get("computed_rating") else "")
    row("Content rights", "OK" if s.get("content_rights") else "MISSING")
    row("Price Free", "OK" if s.get("price_free") else "MISSING")
    av = s.get("availability")
    row("Availability (all territories + new)", "OK" if s.get("avail_ok") else "MISSING",
        f"{av[0]}/{av[1]} territories, new territories {av[2]}" if av else "")
    row('iPhone 6.9"/6.7" screenshots', "OK" if s.get("shots_iphone", 0) >= 1 else "MISSING",
        f"{s.get('shots_iphone', 0)} complete — retake from the final build")
    row("Apple Watch screenshots (app has a Watch app)", "OK" if s.get("shots_watch", 0) >= 1 else "MISSING",
        f"{s.get('shots_watch', 0)} complete")
    row("Build attached", "OK" if s.get("build_ok") else "MISSING", s.get("build") or "attach mode after the final build")
    if s.get("build"):
        row("Export compliance answered", "OK" if s.get("build_encryption") is not None else "MISSING", str(s.get("build_encryption")))
    row("App Review notes", "OK" if s.get("notes") else "MISSING")
    row("App Review contact (name/phone/e-mail)", "OK" if s.get("contact") else "OWNER", "present" if s.get("contact") else "absent")
    row("App Privacy questionnaire", "OWNER", "not readable through the API: 'Data Not Collected'")
    row("Agreements / tax / banking", "OWNER", "not in the API; Free Apps agreement — check the Business page")
    row("No review submission exists", "OK" if not s.get("submissions") else "CHECK", ", ".join(map(str, s.get("submissions") or [])))
    out("SUBMISSION READINESS (Apple validates the rest when the owner presses Add for Review):")
    w = max(len(r[0]) for r in rows)
    for item, ok, detail in rows:
        out(f"  [{ok:^7}] {item.ljust(w)}  {detail}".rstrip())
    missing = [r[0] for r in rows if r[1] in ("MISSING", "DIFFERS")]
    owner = [r[0] for r in rows if r[1] == "OWNER"]
    out(f"  -> {len(missing)} missing for the script/CI, {len(owner)} owner items")


# ------------------------------------------------------------------------------------------------ main
def main():
    for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"):
        if not os.environ.get(k, "").strip():
            out(f"App Store Connect secret {k} missing — nothing done.")
            return 1
    if MODE not in ("check", "apply", "attach", "screenshots"):
        out(f"unknown MODE {MODE}")
        return 1
    asc.TOKEN = asc.token()
    out(f"Cyclift App Store Connect — mode {MODE.upper()} (drafts only; never submits, releases, accepts agreements or sets a paid price)")
    out()
    local_texts()
    out()
    app_id = asc.find_app()
    if not app_id:
        problem("App Store Connect app record not found")
        return finish()
    st, res = call("GET", f"/v1/apps/{app_id}")
    attrs = res.get("data", {}).get("attributes", {}) if st == 200 else {}
    primary = attrs.get("primaryLocale") or "en-US"
    out(f"App record: found; store name {shown_name(attrs.get('name'))}, primary language {primary}")
    app_level(app_id, attrs)
    out()
    out("App information:")
    app_info(app_id, primary)
    out()
    out("Pricing and availability:")
    pricing(app_id)
    availability(app_id)
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
        if MODE == "attach":
            out()
            out("Build attachment:")
            attach(app_id, vid)
            st, r = call("GET", f"/v1/appStoreVersions/{vid}/build")
            b = (r.get("data") or {}) if st == 200 else {}
            if b:
                STATE["build"] = f"{b['attributes'].get('version')} ({b['attributes'].get('processingState')})"
                STATE["build_ok"] = b["attributes"].get("processingState") == "VALID"
                STATE["build_encryption"] = b["attributes"].get("usesNonExemptEncryption")
        if lid:
            out()
            out("Screenshots:")
            summary = screenshot_sets(lid)
            if MODE == "screenshots":
                upload_screenshots(lid, summary)
                out("  after upload:")
                screenshot_sets(lid)
    out()
    out("Builds and review submissions (read only):")
    extras(app_id)
    out()
    readiness()
    return finish()


def finish():
    out()
    out("Problems: " + (str(len(PROBLEMS)) if PROBLEMS else "none"))
    for p in PROBLEMS:
        out("  - " + p)
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(LINES) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
