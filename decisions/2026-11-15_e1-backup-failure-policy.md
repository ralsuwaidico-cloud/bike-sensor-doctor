# E1 backup failure policy

Status: **Implemented on a holding branch, awaiting owner confirmation** · 15 Nov 2026
Scope: the iPhone app's one data file (`store.json`) and its safety copies. No storage redesign.
Code: commit `9f19af51` on `fix/e1-held-validation` (not on `ios/e1-safety`, not in any build).
Evidence: see the last section. Nothing here has run on iOS or on a physical device yet.

## The rule

Cyclift does not transform an existing healthy data file unless the file as it is has first been copied and the copy has been read back and found identical. An ordinary save does not wait for that copy.

## The seven questions

**1. Is a backup mandatory before a potentially destructive write?**
Yes, for the three launch-time changes that rewrite or remove existing data: a schema migration, dropping records that could not be read, and the one-time plan clean-up. No, for an ordinary save (question 7).

**2. Does a failed backup prevent the primary write?**
For those three changes, yes. The change is not made, nothing is written, and the app shows a recovery screen that says so ("could not keep a safety copy first, so it has changed nothing"). The athlete's data is still loaded, only not changed. Try again, or opening the app again, completes the change once a copy can be kept.

**3. New installation with no backup?**
There is nothing to protect, so no copy is required and none is made. The first saves of a new athlete go through normally.

**4. Previous copy stale, missing or unreadable?**
The policy never relies on an older copy. Before a transforming change it makes a fresh one from the current file and checks it. A missing or damaged older copy is simply replaced; a copy that cannot be written blocks the change (question 2). The copy is written in one step, so a failed attempt leaves the older copy as it was.

**5. Can repeated writes replace the only recoverable backup?**
- Within one launch: no. The copy is taken once, before the first write, and later saves do not touch it.
- Across launches: yes, by design. The previous copy follows the file forward, so it always holds the state at the start of the most recent launch that wrote something. It is only ever made from a file that opened correctly, so a damaged file cannot replace it.
- Because that copy moves, a schema migration also keeps the older file under its own name (`store.schema-3.json`), which is never replaced. The clean-up needs no second copy: what it removes goes to the in-app trash with a keep flag and can be restored.

**6. How does the app report and recover?**

| Situation | What the athlete sees | What happens to the data |
|---|---|---|
| Copy cannot be made before a transforming change | Recovery screen with the reason and Try again | Nothing changed, nothing written |
| Copy cannot be made before an ordinary save | Banner: no safety copy could be made this time | The save goes through |
| Ordinary save fails | "Not saved" on the screen that saved | File unchanged; the session is not shown as stored; retry is not a duplicate |
| File unreadable at launch | Recovery screen: Try again, Restore previous copy, Send file, Start again | File left as it is; a byte-for-byte copy kept |

**7. Which operations require a backup?**

| Operation | Copy required first | Why |
|---|---|---|
| Schema migration | Yes, plus the permanent older-schema copy | Rewrites every record |
| Dropping unreadable records | Yes, and the raw records are also set aside | Removes data from the file |
| One-time plan clean-up | Yes | Changes the athlete's plan |
| Restore previous copy, Start again | The unreadable file is copied first (already in E1) | Replaces the file |
| Ordinary saves: workout, ride, plan edit, settings | No; attempted, and reported if it fails | See below |
| Delete all data | No | The athlete asked for everything to go, copies included |

**Why ordinary saves differ.** The save replaces the file in one step, so a failure leaves the old file whole, and it adds to the data rather than transforming it. Refusing to store a finished workout because a spare copy could not be made would lose more than it protects. The cost: after such a save the previous copy is one launch older than it should be, and the athlete is told.

## Limits

- A copy on the same phone does not protect against losing the phone or deleting the app.
- If storage is completely full, the first launch of this version cannot run its clean-up and shows the recovery screen until space is freed. The data stays loaded and unchanged.
- Power loss in the middle of a write cannot be simulated faithfully and is untested.

## Evidence

- Fast logic run 87 on `9f19af51` (Linux): 416 tests executed, 0 failed, 2 skipped. The six policy tests ran and passed: no change without a copy (clean-up, migration, unreadable records), ordinary save still works and says so, older-schema file kept and never replaced, new installation needs no copy.
- The two skipped tests need a folder that is truly read-only and can only run on iOS.
- iOS: pending (full run on `9f19af51`).
