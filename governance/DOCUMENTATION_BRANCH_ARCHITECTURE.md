# Documentation branch — how it is built and what I recommend

Status: Current Draft · 12 Nov 2026. Explanation and recommendation only. The branch has not been recreated, deleted,
merged or moved, and will not be without approval.

## 1. What exists

`docs/cyclift-governance` is an **orphan branch**: it was started empty, with no parent commit, so it shares no
history with `main`, the release branch or any other branch. It contains only documentation files.

## 2. Why I chose that

| Reason | Detail |
|---|---|
| Your instruction | "Use an isolated documentation branch. Do not modify the release branch." An orphan branch is the strongest form of isolation |
| No build can be triggered | The application workflows start on pushes to branches matching `ios/**`, `impl/**` and similar, and live in the application tree. An orphan branch contains no workflow files at all. I confirmed that nothing ran when it was pushed |
| No accidental code | The branch cannot carry, change or revert application or firmware files, because it has none |
| No single obvious parent | The repository has 51 branches and several independent lines (iPhone, Waveshare firmware, Watch, Android, UI Lab). `main` is not where the iPhone app is developed; the release line is `ios/checkpoint-f-ride`. Any parent I picked would have tied the documentation to one workstream |
| Precedent in this repository | `proto/ui-lab`, `proto/ui-lab-out` and `ci-logs` are already orphan branches used for isolated content |

## 3. The costs of that choice

| Cost | Effect |
|---|---|
| It cannot be merged normally | Git refuses to merge unrelated histories unless forced; a forced merge would bring the documents in at the repository root, where `README.md` would collide with the existing one |
| Documentation and code never appear in the same commit | A change to behaviour and the change to its specification cannot be reviewed together |
| Links are by branch name and path, not relative | The index must say "release branch: `ios/OWNERSHIP.md`" instead of linking the file |
| Existing documents cannot be given a status line here | They live on other branches |

## 4. How documentation would reach the application repository

It is already **in** the application repository — as a separate branch. There are three ways it could relate to code:

| Option | How it works | For | Against |
|---|---|---|---|
| **A. Stay a permanent, separate documentation branch** (as now) | Governance, Brand Book and product specifications live only here. Code branches keep their technical documents. The index joins them | Safest; nothing can affect a release; simple to explain | Never in the same commit as code; cannot be merged |
| **B. Normal branch from the main development history** | Recreate the branch from the development line, with the documents under a folder such as `docs/cyclift/`; merge into the development line by pull request | Documents travel with code; relative links; one history; status lines can be added to old documents in the same place | Every documentation merge lands on a code line (must be marked to skip builds); "which line is main?" must be settled first; the branch would carry the whole application tree |
| **C. Hybrid** | Keep this orphan branch as the working and review space; when a document is approved, copy it into a `docs/cyclift/` folder on the development line in one reviewed commit | Isolation while drafting; approved documents end up beside the code | Two places again unless the rule "approved lives with code, drafts live on the docs branch" is kept strictly |

## 5. Is a normal branch more maintainable?

**In the long run, yes — for approved, stable documents.** Specifications that describe shipped behaviour are easiest
to keep true when they change in the same pull request as the code. An orphan branch will drift from the code more
easily, because nothing forces the two to move together.

**Today, not yet**, for three reasons:
1. There is no agreed single development line. `main` does not carry the current iPhone work; the release branch is
   under a stabilisation freeze and must not receive unrelated commits.
2. Almost everything on the documentation branch is a draft under review. Drafts do not belong on a release line.
3. A normal branch needs a decision about build triggers, so that a documentation-only merge can never start a
   TestFlight or firmware pipeline.

## 6. Recommendation

1. **Keep `docs/cyclift-governance` as it is for now** — the drafting and review space, and the authoritative source
   while documents are drafts.
2. **Decide the development line** (which branch is "main" for the iPhone app after the release is stabilised). This
   is a repository decision I should not make alone.
3. **After the release is stable**, adopt option C: approved documents are copied to `docs/cyclift/` on the
   development line in a reviewed, build-skipping commit; this branch remains for drafts.
4. Do not force-merge unrelated histories.

Nothing in this recommendation is carried out without your approval.
