# ui/ — LVGL 8 rendering layer (W1)

Design tokens (`tokens.hpp`, generated from the shared Cyclift / Sport / Bloom families × dark / light and the FIXED
four grading colours), the orbital layout helpers for the round 240 × 240 display, the three watch faces (Orbit, Chrono,
Pulse), the activity screens and the quick-settings sheet. The UI only reads domain state and emits `Gesture`s to the
`Navigator`; it never owns workout data. `lv_conf.h` configures LVGL for a half-screen (57.6 KB) draw buffer in internal
RAM, 16-bit colour, software rotation off.
