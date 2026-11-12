# Tracker status audit — and proposed corrections

Status: Current Draft · Version 0.1 · 12 Nov 2026 · Level 5
Rule followed: no tracker was updated, and no progress was guessed. Each line says what the tracker claims, what
verifiable evidence I found, and what I propose. Where I could not verify, it says so.

| Tracker | Location | Last updated (as written in the file) | Finding | Evidence | Proposed correction |
|---|---|---|---|---|---|
| `CYCLIFT_WORK_STATUS.md` | release branch | 28 Oct 2026 | **Stale.** Speaks of "RC2" and firmware 0.7.4-rc5 awaiting approval | Later record: TestFlight build 216 is the baseline (decision 10 Nov; build-216 audit). Whether firmware 0.7.4 was ever installed: **not verified by me** | Label Historical in the index (done there as a proposed label). Do not edit the file. If a live dashboard is wanted, create a new one from evidence |
| `coord/TASKBOARD.md` | release branch | 27 Oct 2026 | **Stale.** Tasks FW-1 … INT-1 shown as running or todo | No later update in the file; outcomes of those tasks **not verified by me** | Same: Historical (proposed label); no edit |
| `iphone-app/APP_COMPLETENESS_AUDIT_BUILD216.md` | project (+ repo copy) | 10 Nov 2026 | Current for build 216 | Cites CI runs 214–216 and test names | Keep. One addition proposed: Defect 6 — fix committed after 216, Apply path **not validated** (runs 217–221), three owner decisions open |
| `ios/APP_COMPLETENESS_AUDIT.md` | release branch | 10 Nov 2026 | Same subject as the project copy | Not compared line by line | Name one authoritative (GitHub, per the source-of-truth decision) and make the project copy a labelled reference copy — at migration |
| `hardware-design/FEATURE_REGISTRY_102.md` | project | 8–10 Nov 2026 | Registry of 102 features with placement | Referenced by later readiness documents | Keep; not re-audited here |
| `hardware-design/WATCH_STAGE2A_READINESS.md` | project | 11 Nov 2026 | Records an install and hardware validation that **stopped on defects** | Its own text | Keep; hardware-design workstream owns it |
| `CYCLIFT_HARDWARE_HANDOVER/06_IMPLEMENTATION_STATUS.md` | hardware-handover branch | 10 Nov 2026 | Per-feature status with explicit hardware-verified column | Opened only the first rows | Keep; not re-audited here |
| `ui-lab/home-v2.2/HOME_REVIEW_TRACKER.md` | project | 12 Nov 2026 | 80 rows, all "Awaiting owner review"; cites interaction-test run 43204124295 (iPhone 17: 22 of 22; iPhone SE: 20 of 22) | Run output on `proto/ui-lab-out` at the time | Keep. A v2.3 tracker follows when its verification run is reported |
| `planning/…/E_COACHING_VERIFICATION_MATRIX.md` | project | 11 Nov 2026 | States per case whether behaviour is met today, partly, or not yet | Derived from the code audit A | Keep |
| `ios/CHANGELOG.md` | release branch | Top entry dated 26 Oct 2026 (1.0.0 / build 58) | **Possibly incomplete**: builds up to 216 exist, the top of the changelog does not mention them | Only the first lines were read | Verify the whole file before proposing any edit — **not verified** |

## Proposed corrections that need your approval (none made)

1. Mark the two October dashboards Historical in the files themselves (one line at the top).
2. Add the Defect 6 status line to the build-216 audit.
3. Decide whether a single live project tracker should replace the two October dashboards.
4. Verify `ios/CHANGELOG.md` against the build history before touching it.
