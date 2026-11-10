# Cyclift Watch — rollback and recovery for Stage 1.3 RC1 (11 Nov 2026)

**None of these steps is approved.** Each physical write needs the owner's separate approval naming it. Everything below is
tested only in the computer simulation (`watch/tools/stage2a/test_reinstall_sim.py`, sections 9–10) and the boot emulator
(CI job boot-sim, scenario S10). Physical rollback has been exercised before only for Stage 1 → layout (B1, 9 Nov).

## Starting point (watch today)
- app0 0x10000 = factory LILYGO firmware (byte-identical to the backup, fingerprint 77ad7105…).
- app1 0x400000 = **Stage 1.1** `3274b887…` (installed 10 Nov, C1). OTA record selects app1.
- Files kept on the owner's PC (never uploaded): flash backup, approved Stage 1 `faa2828f…`, installed Stage 1.1
  `3274b887…`, Stage 1.2 candidate `2760f5a7…` (never installed), and — after approval — RC1.

## The RC1 update (for reference)
`cy_update_s13.py`: `s13_pre` (read-only checks, whole-flash read, baseline boot) → `s13_write` (ONE write at 0x400000,
the larger of Stage 1.1 / RC1 padded to 4 KB sectors; verify; boot confirmation "Stage 1.3") → `s13_post` (whole-flash
read; only the app1 span may differ). No erase command, no bootloader, partition table or OTA write.

## Recovery ladder (try in order; stop at the first that works)

| # | Situation | Action (tool phase) | Writes | Result |
|---|---|---|---|---|
| 1 | RC1 runs but the owner rejects it | `s13_rollback` | app1 span only | Stage 1.1 back, boot "Stage 1.1" confirmed |
| 2 | Stage 1.1 also unwanted | `s11_rollback` (cy_update_s11) | app1 span only | approved Stage 1 back |
| 3 | RC1 write interrupted / app1 damaged | none needed to boot: the bootloader finds no valid app1 image and starts factory app0 (emulator S10). Then repeat `s13_write` or do #1 | — | factory firmware runs; Cyclift reinstall possible |
| 4 | Cyclift must not start any more | R-A (`cy_install.recovery('RA')`) | OTA record (2 sectors) | original OTA record; factory app starts |
| 5 | Return to the factory layout | R-B (`cy_recover_b`: rb_precheck → rb_restore → rb_confirm) | bootloader, table, OTA from the backup pieces | factory layout, factory app starts; accepts Stage 1, 1.1, 1.2 or RC1 in app1 |

Simulation evidence (computer, 11 Nov): RC1 update = exactly one write at 0x400000; first 4 MB untouched; rollback to
Stage 1.1 and further to Stage 1; R-A and R-B after RC1; a verify failure stops the phase and restarts the watch; wrong
fingerprint refused; an unpinned tool (`NOT_PINNED`) refuses every file; a watch not running Stage 1.1 refused —
52 checks in the simulation, 0 failures.

## Stop rules (from the C1 conditions, kept)
Stop at the first failed check; no improvised writes; the owner approves every write; boot button (IO0) untouched during
restarts; COM4 used by one program only.
