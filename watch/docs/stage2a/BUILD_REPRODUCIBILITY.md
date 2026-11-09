# Stage 1 build reproducibility (9 Nov 2026)

## Finding
Two CI builds of the same source (V1_1 v3poc) — approved `faa2828f…cba7` and a fresh build `ede6f9f8…` (run 42650179036) —
differ in **36 bytes**, all in the first data segment (flash read-only data, 0x3F400020). Code segments, RAM segments and the
image header are byte-identical.

| Offset in segment 0 | Bytes | Content | Origin |
|---|---|---|---|
| +144 | 32 | `app_elf_sha256` in the ESP-IDF application descriptor | hash of the ELF file — changes whenever any byte of the ELF changes |
| +178 949 | 8 (2 runs of differing chars) | compile time `"12:20:13"` vs `"16:03:15"`, next to `"Nov  9 2026"` | `__TIME__`/`__DATE__` in the Arduino-ESP32 3.3.12 core's start-up report (`Software Info:` / `Compile Date/Time : %s %s`, chip debug report) — framework code, not Cyclift code (no `__DATE__`/`__TIME__` in `watch/firmware/src`) |

Cause: **build timestamps only** (the time string, and the ELF hash that changes because of it). Toolchain, library versions,
dependencies and compiled code are identical (versions pinned and checked by `check_versions.py`). Earlier identical rebuilds
came from cached object files that still held the old time.

The approved file `faa2828f…` is unchanged and remains the only approved Stage 1 binary; it is kept in the
`firmware/stage1-candidates` branch and on the PC.

## Proposed fix (not applied — changes the binary, so it needs a new approval cycle)
1. Add to the device build flags: `-Wno-builtin-macro-redefined -D__DATE__=\"Jan__1_2026\" -D__TIME__=\"00:00:00\"`
   (PlatformIO passes `build_flags` to the framework sources too), or set `SOURCE_DATE_EPOCH` if the toolchain honours it.
2. CI: build the V1_1 image twice without cache and fail if the SHA-256 differs.
3. Only after this, a new candidate would replace `faa2828f…` — through the normal review and owner approval.
