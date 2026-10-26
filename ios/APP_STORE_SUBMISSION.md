# Cyclift 1.0.0 — App Store submission guide (for Rashed)

Everything that can be done safely through Apple's API has been done by the **App Store listing** workflow
(`ios/ci/asc_listing.py`). Nothing has been submitted, nothing is released, no agreement was accepted and nothing costs
money. The steps below are the ones only you can do, in plain language, in the App Store Connect website
(https://appstoreconnect.apple.com → **Apps** → **Cyclift**).

Latest reports: branch `ci-logs`, folder `ios/asc-listing/run-N/report.txt` (highest N = newest). Each report ends
with a **SUBMISSION READINESS** list: OK = done, MISSING = still to do by Claude/CI, OWNER = yours.

## Already set (drafts, by the workflow)
| Item | Value |
|---|---|
| Name / subtitle | Cyclift / "Ride, lift and plan your week" |
| Category | Health & Fitness (primary), Sports (secondary) |
| Description, keywords, promotional text | from `ios/store/en-US/` — no accounts, no sync, no "coming soon", no medical or AI claims |
| Support / marketing / privacy URLs | https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/support.html · …/index.html · …/privacy.html |
| Copyright | 2026 Cyclift |
| Age rating | all content questions "None"; Health/wellness topics "Yes" (fitness training) → Apple computes **4+** |
| Content rights | "Does not use third-party content" |
| Price | **Free** (base country United States), no in-app purchases |
| Availability | all 175 countries/regions, and new countries automatically |
| Release | **Manual** — after approval the app waits for you to press Release |
| App Review notes | written in `ios/store/en-US/review_notes.txt`; Apple only saves them **after** the contact fields exist (step 2) |
| Screenshots | 5 iPhone screenshots (from the pre-1.0 build) — will be retaken from the final build |

## Your steps, in order

### 1. Publish the website pages (one switch on GitHub)
The support/privacy links in the listing must open, otherwise Apple rejects the app.
GitHub → repository **bike-sensor-doctor** → **Settings** → **Pages** → *Source*: **Deploy from a branch** →
Branch: **ios/dev** (or **main** once merged), folder **/docs** → **Save**. After 1–2 minutes these must open:
https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/privacy.html and …/support.html and …/index.html
(The last check found all three "404 — not published yet".)

### 2. App Review contact (needed before the review notes can be saved)
App Store Connect → **Cyclift** → left column **iOS App › 1.0 Prepare for Submission** → scroll to
**App Review Information** → *Contact Information*: First name, Last name, Phone (start with **+971…**), Email →
leave **Sign-in required** unticked (no account is needed) → **Save** (top right).
Then tell Claude "re-run the listing apply" — the full review notes are written automatically. (Or paste the text of
`ios/store/en-US/review_notes.txt` into the **Notes** box yourself.)

### 3. App Privacy — answer "Data Not Collected"
Cyclift 1.0 keeps all data on the iPhone, sends nothing to any server, and contains no third-party SDK that collects
data. Apple's API cannot fill this page, so:
App Store Connect → **Cyclift** → left column **App Privacy** → next to *Data Types* click **Get Started** →
choose **"No, we do not collect data from this app"** → **Save** → back on the App Privacy page click **Publish**
(top right). The *Privacy Policy URL* on that page should already show …/site/privacy.html.

### 4. Agreements, tax and banking
Free apps only need the **Free Apps Agreement**, which Apple accepts automatically with the developer membership.
Apple's API cannot show agreements, so look once: App Store Connect home → **Business** (or *Agreements, Tax, and
Banking*). If the *Free Apps* row says **Active**, you are done. If a yellow banner asks you to accept an updated
agreement, read and accept it yourself (Claude never accepts agreements). Paid-apps tax/banking forms are **not**
needed for a free app — leave them.

### 4b. EU "trader status" (Digital Services Act) — needed to sell in the 27 EU countries
Apple's API reports `TRADER_STATUS_NOT_PROVIDED` for the EU territories: until you answer, Cyclift is not offered in
the EU (all other countries are unaffected). App Store Connect home → **Business** → **Digital Services Act
Compliance** (or the banner that mentions it) → **Complete Compliance Requirements** → choose:
- **"I'm not a trader"** if Cyclift is a private, non-commercial project (free, no business behind it), or
- **"I'm a trader"** if you publish it as a business — then Apple shows an address, phone number and e-mail **publicly**
  on the EU App Store page and verifies them.
This is your decision (a legal self-declaration, not legal advice here). If you would rather not answer now, the app
can still be submitted; it simply will not appear in EU countries until you do.

### 5. Build and screenshots (Claude does these once the final 1.0.0 build exists)
When the final release-candidate build is on TestFlight and you have tested it, Claude runs:
- `asc-listing/attach-<build number>` — waits until Apple has processed the build, answers export compliance (no
  special encryption) and selects it on the 1.0 page;
- `asc-listing/screenshots` — new screenshots from the final app (9:41 status bar, ride screen in dark mode) plus an
  Apple Watch screenshot (Apple asks for one because the app includes a Watch app).
Then **you look at the screenshots**: 1.0 Prepare for Submission → *Previews and Screenshots* (iPhone 6.9" and Apple
Watch tabs). If one looks wrong, tell Claude; you can also delete one with the × on it.

### 6. Final check, then submit — only when you decide
On the **1.0 Prepare for Submission** page check: build selected, screenshots, description, App Review contact.
Then **Add for Review** (top right) → on the next page **Submit for Review**. Apple usually answers in 1–3 days by
e-mail. Claude will never press these buttons.

### 7. Release after approval
Because the release type is *Manual*, an approved app shows **Pending Developer Release**. When you are ready:
1.0 page → **Release This Version** → confirm. The app is in the App Store within a few hours.

## App Privacy answers (reference)
| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app** |
| Tracking | none (no tracking, no ads, no analytics) |
| Why "not collected" is correct | All training data, Health data and ride locations stay on the iPhone; HealthKit is read/written only on the device with permission; there is no account, no server, no analytics and no third-party SDK that collects data in 1.0. Export and "Delete all data on this phone" are local. |
| When this must change | 1.1 with accounts + sync: then Contact Info (e-mail), Health & Fitness, Location, Identifiers, User Content become "collected, linked to the user, app functionality, not tracking" — update App Privacy **before** submitting 1.1. |

## For Claude/CI: how to run the workflow
Push a commit (its message must **not** contain `[skip ci]`) to a trigger branch; cancel the "Build APK" run the push
also starts. Example from the `ios/rel-asc` (or later `ios/dev`) checkout:

```
T=$(git commit-tree HEAD^{tree} -p HEAD -m "asc-listing: run check")
git push -f origin $T:refs/heads/asc-listing/check            # or asc-listing/apply
git push -f origin $T:refs/heads/asc-listing/attach-61        # attach build 61 of 1.0.0
git push -f origin $T:refs/heads/asc-listing/screenshots      # screenshots of the app code on ios/dev
```
Once the workflow file is on the default branch: `gh workflow run asc-listing.yml --ref ios/dev -f mode=screenshots`
(app code = `--ref`; `-f app_ref=<ref>` overrides it) or `-f mode=attach -f build=61`.
