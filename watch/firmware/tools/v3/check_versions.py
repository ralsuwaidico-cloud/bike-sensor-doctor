#!/usr/bin/env python3
"""Fail if the PlatformIO build resolved to toolchain / framework / library versions other than the pinned ones.

Usage (in watch/firmware, after building):  python3 tools/v3/check_versions.py ENV [ENV ...]
It runs `pio pkg list -e ENV` and compares every pinned name with the version PlatformIO actually installed.
"""
import json
import os
import re
import subprocess
import sys

PIN = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "pinned_versions.json")))
LINE = re.compile(r"([A-Za-z0-9_.\-]+) @ ([0-9A-Za-z.+\-]+)")


def found(env):
    out = subprocess.run(["pio", "pkg", "list", "-e", env], capture_output=True, text=True).stdout
    seen = {}
    for name, ver in LINE.findall(out):
        seen.setdefault(name, set()).add(ver)
    return seen, out


def compare(env, seen):
    want = dict(PIN["platform"])
    want.update(PIN["packages"])
    want.update(PIN["libraries"].get(env, {}))
    problems = []
    for name, ver in want.items():
        got = seen.get(name)
        if not got:
            problems.append("%s: %s not found (expected %s)" % (env, name, ver))
        elif got != {ver}:
            problems.append("%s: %s is %s, pinned %s" % (env, name, ", ".join(sorted(got)), ver))
    return problems


def self_test():
    sample = {"espressif32": {"8.0.0"}, "framework-arduinoespressif32": {"4.30312.261024"},
              "framework-arduinoespressif32-esp32-libs": {"3.3.12"}, "toolchain-xtensa-esp-elf": {"14.2.0+20260121"},
              "tool-esptool": {"2.50400.0"}, "TFT_eSPI": {"2.5.43"}, "lvgl": {"8.3.11"}, "NimBLE-Arduino": {"1.4.3"}}
    ok = compare("T-Watch-2021-V1_1-v3poc", sample) == []
    drift = dict(sample, **{"framework-arduinoespressif32": {"4.30400.0"}})
    caught = compare("T-Watch-2021-V1_1-v3poc", drift) != []
    print("version check self-test:", "PASS" if ok and caught else "FAIL")
    return 0 if ok and caught else 1


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    problems = []
    for env in sys.argv[1:]:
        seen, _ = found(env)
        p = compare(env, seen)
        print("%s: %s" % (env, "versions as pinned" if not p else "; ".join(p)))
        problems += p
    print("version check:", "PASS" if not problems else "FAIL (%d)" % len(problems))
    sys.exit(1 if problems else 0)
