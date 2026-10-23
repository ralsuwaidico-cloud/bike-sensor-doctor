# PC preview and round-screen UI test

Runs the real firmware UI and app code (`main/ui`, `main/app`, `components/bc_core`) on LVGL built with the firmware's
own `build/config/sdkconfig.h`. Run an ESP-IDF build once first.

    make run                 # builds liblvgl.a + sim, runs the scripted scenario, writes out/*.ppm and out/report.txt
    python3 sheet.py out     # PNG previews (round glass mask) and contact sheets

Every captured screen is checked for: pixels outside the round glass (CIRCLE), characters missing from the font (GLYPH),
text/controls cut off by their parent (CLIP), controls too small or too close to the edge (TOUCH).
The scenario also asserts onboarding, persistence across restart, ride start/pause/resume/end, hold-to-confirm,
NO DATA states, demo isolation, crash/power-loss recovery and the FTP rules. Sensor values come from the harness
(scripted stand-ins), never from real hardware.
