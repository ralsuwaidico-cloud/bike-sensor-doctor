# Cyclift — development and CI process (owner instruction 2 Nov 2026, point 3)

Goal: stop discovering outdated expectations and compile errors inside two-hour release runs, without weakening a single
release-blocking gate. Every gate from `ios/CI_PIPELINE.md` stays: unit tests, launch/smoke, the four layout audits incl.
iPhone SE at AX3, the design-system accessibility audit, the three recorded journeys, migration and data-integrity tests,
archive verification; the release job still runs only when every test job passed.

## The developer loop

```
edit → tools/precommit.sh → commit with [ci quick] → quick run green → commit/retag with [testflight] → full run → TestFlight
```

1. **`tools/precommit.sh` before every commit** (required). It runs, on the changed files:
   - `swiftc -parse` on every changed Swift file (catches syntax before CI — the only compile we have on Linux);
   - the Linux engine harness, filtered to the suites that cover the changed files (`tools/ci-targets.py --harness`), from a
     clean copy of `tools/coach-harness` exactly as the Fast-logic workflow runs it (run 129's shim mismatch would have been
     caught here); `--full` runs every suite;
   - `actionlint` + `bash -n` + `py_compile` for workflow, shell and Python changes.
   It exits non-zero on any failure and prints where the log is.
2. **Commit with `[ci quick]`.** The quick job compiles, runs all unit tests on the simulator, then only the UI tests that
   cover the files changed since the last green full run (`tools/ci-targets.py --quick-ui` on `git diff <last-green>..HEAD`),
   on iPhone SE (AX3) and a standard iPhone (L), and records the hybrid journey. ~15–25 min for a small change. The mapping
   lives in `tools/ci-targets.py` (edit it when a new screen or test file appears); an app file with no rule falls back to the
   default quick set plus every harness suite — never to nothing. `workflow_dispatch` with `quick_ui` still overrides.
3. **Only after the quick run is green, request the full pipeline** (`[testflight]` in the commit message, or dispatch with
   upload = true). The release job **refuses to archive** unless the ci-logs branch holds a green quick marker for HEAD's
   *source tree* (`ios/ci/quick-green/<tree-hash>`). Keying on the tree hash means re-tagging the same code with
   `[testflight]` (a new commit, same tree) is accepted; any source change needs its own quick run. Escape hatch for a real
   emergency only: `[full-override: <reason>]` in the commit message — the reason is printed in the summary and the test
   gates are unchanged (the override skips the *quick-first* rule, never a test).
4. **Markers** are written by the publish job into the `ci-logs` branch (not the source branch, so nothing re-triggers CI):
   `ios/ci/quick-green/<tree>` after a green quick run, `ios/ci/last-green.txt` (commit) after a green full run. The next
   quick run diffs against `last-green` to pick its targets.

## What runs where

| Check | precommit (Linux, minutes) | quick (CI, ~20 min) | full (CI, ~50 min + Apple) |
|---|---|---|---|
| Swift syntax | changed files | compile (Debug + Release) | compile |
| Engine harness (Host) | affected suites / `--full` | — (Fast-logic workflow runs it on every push) | — |
| Unit tests (Unit-sim) | — | all | all |
| UI tests (UI-sim) | — | targeted + hybrid journey (SE AX3, standard L) | all smoke + 3 recorded journeys + 4 layout devices + design-system audit |
| Watch screenshots | — | — | yes |
| Archive / sign / verify / upload / TestFlight processing | — | never | only with every test job green and a green quick marker |

## Rules that do not change

- No test is deleted or relaxed to make a run pass. A test that contradicts `ios/BEHAVIOUR_CONTRACT.md` is listed there as an
  outdated candidate and rewritten to the contract (data assertions), never to the old behaviour.
- A failure is classified before anything is pushed: app defect / outdated test / timing / infrastructure. Timing failures
  get a wait-for-element fix (`UITestWaits`), never a `sleep` or a retry loop; infrastructure retries stay limited to the
  existing "simulator could not launch" rule.
- Simulator results are never reported as device results; nothing is "hardware tested" without the physical device.
- Cosmetic findings do not restart a healthy full run; they go into the next quick cycle.

## Files

- `tools/precommit.sh` — the required pre-commit check.
- `tools/ci-targets.py` — changed paths → UI tests (`--quick-ui`), harness suites (`--harness`), both with reasons (`--json`).
- `ios/ci/build.sh` — `quick_targets` (quick stage), `quick_green_for_head` + the archive refusal (release / all stages).
- `.github/workflows/ios.yml` — `HEAD_MSG` for the quick and release jobs; the publish job writes the markers.
