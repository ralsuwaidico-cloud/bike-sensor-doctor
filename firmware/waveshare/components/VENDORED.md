# Vendored components (copied 2026-10-23, component manager disabled)

| Component | Source | Version |
|---|---|---|
| lvgl | github.com/lvgl/lvgl tag v9.3.0 (demos/examples/tests/docs and non-cmake env_support removed) | 9.3.0 |
| esp_lvgl_port | github.com/espressif/esp-bsp components/esp_lvgl_port @ f259a6a | 2.9.0 |
| esp_lcd_gc9a01 | github.com/espressif/esp-bsp components/lcd/esp_lcd_gc9a01 @ f259a6a | 2.0.4 |
| esp_lcd_touch | github.com/espressif/esp-bsp components/lcd_touch/esp_lcd_touch @ f259a6a | — |
| esp_lcd_touch_cst816s | github.com/espressif/esp-bsp components/lcd_touch/esp_lcd_touch_cst816s @ f259a6a | 1.1.2 |

Local change: the `include(package_manager)` / `cu_pkg_define_version()` lines (from the registry-only `cmake_utilities`
component) were removed from the CMakeLists of the esp-bsp components. Licences: LVGL MIT, esp-bsp Apache-2.0.
