# Stage 1.3 RC2 — offline candidate (preserved, never installed)

`cyclift-stage1.3-rc2-v3poc-T-Watch-2021-V1_1.bin`, SHA-256 `82500ce2a2531271573489c9080d7372e0ee97c330e44cbb85f2f3a2040da461`,
1,197,184 B, built from commit 6c07f69 (CI 43064696858, all jobs green); fingerprint pinned in `../stage1.3-rc2.sha256`.
Contents: the D6 clock fix (time shown whenever the clock chip is valid), charge-pin debounce, reset reason and start count,
uptime in `perf:` lines, rebuild-cause log. Prepared offline with the owner's approval of 11 Nov 2026 20:51; installation was
never approved. Superseded on 12 Nov 2026 by the Stage 1.4 button-system candidate, which contains all of RC2.
Kept byte-for-byte; CI checks the fingerprint. Not a rollback image: the installed rollback image is Stage 1.3 RC1 (4ea0ea90…).
