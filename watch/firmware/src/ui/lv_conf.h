/* Cyclift Watch OS — LVGL 8.3 configuration for the GC9A01 240×240 round display */
#ifndef LV_CONF_H
#define LV_CONF_H
#define LV_COLOR_DEPTH 16
#define LV_COLOR_16_SWAP 1
#define LV_MEM_CUSTOM 0
#define LV_MEM_SIZE (64U * 1024U)
#define LV_DISP_DEF_REFR_PERIOD 30
#define LV_INDEV_DEF_READ_PERIOD 30
#define LV_USE_PERF_MONITOR 0
#define LV_TICK_CUSTOM 1
#define LV_TICK_CUSTOM_INCLUDE "Arduino.h"
#define LV_TICK_CUSTOM_SYS_TIME_EXPR (millis())
/* the font ladder used by ui/lvgl_renderer.hpp (sizes map to the largest font ≤ the layout engine's request) */
#define LV_FONT_MONTSERRAT_12 1
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_MONTSERRAT_24 1
#define LV_FONT_MONTSERRAT_28 1
#define LV_FONT_MONTSERRAT_32 1
#define LV_FONT_MONTSERRAT_40 1
#define LV_FONT_MONTSERRAT_48 1
#define LV_FONT_DEFAULT &lv_font_montserrat_14
#define LV_USE_ARC 1
#define LV_USE_LABEL 1
#define LV_USE_BTN 0
#define LV_USE_IMG 1   /* required by lvgl extra widgets (animimg) even though no bitmaps are drawn */
#define LV_USE_LINE 1
#define LV_USE_METER 0
#define LV_USE_THEME_DEFAULT 0
#define LV_USE_FLEX 0
#define LV_USE_GRID 0
#define LV_BUILD_EXAMPLES 0
#endif
