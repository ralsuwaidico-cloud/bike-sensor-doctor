# Cyclift development team — operating protocol

Set up 27 Oct 2026 12:30 (Dubai) on the owner's 12:21 brief. The lead (main conversation) owns this file and TASKBOARD.md.

## What the environment actually supports (inspected, not assumed)
- **Subagents** (Agent tool): real, separate Claude workers with their own context and tools. Several started in one step run
  concurrently. They run only while this session is active; they are not daemons. When one finishes it returns a report to the lead
  and stops. A finished agent can be resumed with its context by name (SendMessage), so work continues from where it stopped.
- **Messaging**: SendMessage between the lead and its subagents (by name). No other Claude sessions run on this machine (ListAgents: none).
- **Task list**: the session task list (TaskCreate/TaskUpdate) is the live board shown beside the chat; TASKBOARD.md is its durable copy in git.
- **Worktrees**: one git worktree + branch per implementation agent.
- **Limits**: 2 CPU cores, 7 GB RAM, ephemeral container (only what is pushed to GitHub survives a container loss). So at most 3 agents at a
  time and heavy jobs (Swift builds, ESP-IDF builds, the 48-athlete harness) are serialised with `flock /home/claude/coord/heavy.lock <cmd>`.
  No physical hardware here: the board, iPhone and Watch are verified only by the owner, with the procedures we deliver.

## Roles
| # | Agent name | Role | Worktree / branch | Owns (files) |
|---|---|---|---|---|
| 1 | lead (main conversation) | Project lead: board, assignments, conflicts, reports, owner approvals | /home/claude/bike-sensor-doctor `ios/dev` (board + status only) | coord/, CYCLIFT_WORK_STATUS.md |
| 2 | ios | iOS & Watch | /home/claude/ws-ios2 `ios/phonefirst-dev` | ios/** except coach engine files |
| 3 | firmware | Firmware & hardware | /home/claude/ws-fw2 `fw/phonefirst` | firmware/**, coord/interfaces/BLE_CONTRACT.md (author) |
| 4 | coach | Coaching engine | /home/claude/ws-coach `fix/coach` (pushed as `ios/coach`) | Planning, StrengthPlanner, AdaptationEngine, CoachSafety, coach tests, coach-harness |
| 5 | qa | Independent QA & science (read-only, adversarial) | /home/claude/ws-review (detached at the commit under review) + own probe files | review reports only; never edits others' code |
| 6 | integration | Integration & release | /home/claude/bike-sensor-doctor `ios/dev` | merges, release packages, rollback procedures, release notes |

## Rules every agent follows
1. Work only in your worktree and owned files; anything outside goes to the lead as a request.
2. Cross-component interfaces live in coord/interfaces/ (BLE_CONTRACT.md). Firmware drafts, iOS reviews; any change is sent to both.
3. Quality gate: implement → commit → test → document → independent QA review → fix findings → hand off to integration.
4. Append one line per meaningful milestone to /home/claude/coord/progress/<agent>.log; write coord/handoffs/<agent>.md in your branch
   when handing off (what changed, commits, tests, open issues). Commit + push your branch at every checkpoint so work survives.
5. Simulated / host / CI results are never described as hardware verification.
6. Never: flash, reset or erase the board; upload TestFlight; publish; send diagnostics to external servers; print personal data in
   the public repo. Those go to the owner through the lead.
7. Heavy commands run under `flock /home/claude/coord/heavy.lock`.
