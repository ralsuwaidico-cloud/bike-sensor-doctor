# Task board (durable copy; live copy = session task list)

Updated 27 Oct 2026 12:30. Status: todo / running / review / ready (for integration) / done / blocked.

| ID | Task | Agent | Pri | Depends on | Status | Branch @ commit | Tests | Blockers / notes |
|---|---|---|---|---|---|---|---|---|
| FW-1 | Measured flash/RAM/storage report; decode 0.7.3 crash with matching ELF; date the FAT root-dir corruption across backups; 0.7.2→0.7.3 diff | firmware | P0 | — | running | fw/phonefirst | — | board flash read needs owner approval (resets board) |
| FW-2 | Crash fixes: BLE init degrades instead of abort; staged boot really disables crashed subsystem; real storage failure categories on recovery screen; safe FS recovery | firmware | P0 | FW-1 | running | fw/phonefirst | host tests + build | — |
| FW-3 | Phone-first architecture + BLE data contract (coach sync, offline ride queue, diagnostics transfer, storage status) | firmware (author), ios (review) | P0 | FW-1 | running | coord/interfaces/BLE_CONTRACT.md | — | — |
| FW-4 | Lightweight device: coach screen in every layout, offline queue, bounded diag storage + transfer/ack/delete | firmware | P1 | FW-3 | todo | | | |
| FW-5 | Stress tests (host + fault injection) | firmware, qa | P1 | FW-2 | todo | | | |
| IOS-1 | Cyclift side of the contract: coach sync sender, offline-ride import, diag auto-transfer + ack, storage screen + safe cleanup | ios | P1 | FW-3 | todo | ios/phonefirst-dev | | starts when contract v1 is drafted |
| CO-1 | 48-athlete harness on 3e801a0 (s8) — read results, fix any regression without weakening criteria | coach | P0 | — | running | fix/coach @ 3e801a0 | s8 running | — |
| CO-2 | CI green on ios/coach for the final head | coach | P0 | CO-1 | running | ios/coach | CI 78 pending | GitHub queue |
| QA-1 | Final independent review of coach head 3e801a0 (pain release, screening, regressions, data preservation) | qa | P0 | — | running | ws-review @ 3e801a0 | | |
| CO-3 | Before/after scientific audit package + GO/NO-GO | coach + lead | P0 | CO-1, CO-2, QA-1 | todo | | | |
| QA-2 | Review firmware FW-2 fixes + BLE contract (both sides) | qa | P1 | FW-2, FW-3 | todo | | | |
| INT-1 | Merge reviewed coach work → ios/dev; coordinated RC (firmware pkg + iOS); compatibility + rollback checks | integration | P1 | CO-3, QA-2 | todo | ios/dev | | owner approval for flash / TestFlight |
