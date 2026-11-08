# Cyclift Watch — wearable OS for the LILYGO T-Watch 2021 (round · T-Micro32 Plus · GC9A01)

Separately tracked workstream (owner directive 8 Nov 2026). Nothing here flashes the watch: flashing, overwriting the
factory firmware and any irreversible hardware change need the owner's explicit approval.

- `docs/HARDWARE_AUDIT.md` — exact hardware, capability matrix, pin maps per revision, programming method (T-U2T),
  factory backup & recovery, non-destructive diagnostics, what to measure
- `docs/ARCHITECTURE.md` — framework choice, module layout, screen & navigation map, BLE design, rep-counting
  strategy, milestones W0–W8 with dependencies and acceptance, tracking
- `docs/WATCH_FACES.md` + `docs/watch-faces.html` — Orbit / Chrono / Pulse in six appearances
- `docs/REP_COUNTING.md`, `docs/BLE_PROTOCOL.md`
- `firmware/` — PlatformIO project: `src/domain` (pure, host-tested), `src/hal` (interfaces + pin maps), `src/ui`
  (LVGL config), `src/app` (W0 diagnostics entry), `boards/partitions_8mb_ota.csv`
- `firmware/test/host` — `make` builds and runs the domain tests on any PC (66 checks)
- `tools/backup_factory_firmware.sh` — read-only full-flash backup (needs the T-U2T dongle)
