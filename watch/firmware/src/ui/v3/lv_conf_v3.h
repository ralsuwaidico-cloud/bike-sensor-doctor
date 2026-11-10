/* Cyclift Watch v3 — LVGL 8.3 configuration for the Stage 1 proof of concept (env T-Watch-2021-*-v3poc and the host tests).
   Differences from ui/lv_conf.h (the existing application, unchanged): Inter / Noto Sans Arabic fonts compiled in from
   ui/v3/fonts (compressed, so LV_USE_FONT_COMPRESSED), right-to-left text and Arabic shaping, image widget for the 8-bit
   alpha icons, only Montserrat 14 kept as LVGL's default font. The host build (CYW_HOST) drives the tick itself. */
#ifndef LV_CONF_H
#define LV_CONF_H
#include <stdint.h>
#define LV_COLOR_DEPTH 16
#define LV_COLOR_16_SWAP 1
#define LV_MEM_CUSTOM 0
#ifndef CYW_LV_MEM_KB              /* computer-only override for the pool-size study (test/v3: make EXTRA=-DCYW_LV_MEM_KB=32U) */
#define CYW_LV_MEM_KB 64U
#endif
#define LV_MEM_SIZE (CYW_LV_MEM_KB * 1024U)
#define LV_DISP_DEF_REFR_PERIOD 30
#define LV_INDEV_DEF_READ_PERIOD 30
#define LV_USE_PERF_MONITOR 0
#ifdef CYW_HOST
#define LV_TICK_CUSTOM 0
#else
#define LV_TICK_CUSTOM 1
#define LV_TICK_CUSTOM_INCLUDE "Arduino.h"
#define LV_TICK_CUSTOM_SYS_TIME_EXPR (millis())
/* LVGL's per-pixel drawing routines (blend, masks) in internal instruction RAM instead of flash (Stage 1.1, 51,404 B of IRAM).
   Stage 1.2 (owner decision 10 Nov): OFF by default — Bluetooth needs that IRAM (the Bluetooth app alone uses 128,424 of
   131,072 B). Only the comparison build T-Watch-2021-V1_1-v3poc-fastmem (never published or flashed) sets CYW_FAST_MEM. */
#ifdef CYW_FAST_MEM
#include "esp_attr.h"
#define LV_ATTRIBUTE_FAST_MEM IRAM_ATTR
#endif
#endif
/* the font ladder used by ui/lvgl_renderer.hpp (sizes map to the largest font ≤ the layout engine's request) */
#define LV_FONT_MONTSERRAT_12 0
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 0
#define LV_FONT_MONTSERRAT_20 0
#define LV_FONT_MONTSERRAT_24 0
#define LV_FONT_MONTSERRAT_28 0
#define LV_FONT_MONTSERRAT_32 0
#define LV_FONT_MONTSERRAT_40 0
#define LV_FONT_MONTSERRAT_48 0
#define LV_FONT_DEFAULT &lv_font_montserrat_14
#define LV_USE_FONT_COMPRESSED 1
/* right-to-left text and Arabic shaping (Arabic is verified on a computer only until Stage 2/3) */
#define LV_USE_BIDI 1
#define LV_BIDI_BASE_DIR_DEF LV_BASE_DIR_LTR
#define LV_USE_ARABIC_PERSIAN_CHARS 1
/* Widgets: only what the renderer draws (arcs, labels, lines). LVGL enables every widget whose LV_USE_* macro is left
   undefined, so each unused one is switched off explicitly — otherwise the calendar / animimg / keyboard code is
   compiled and demands flex, buttons and images. */
#define LV_USE_ARC 1
#define LV_USE_LABEL 1
#define LV_USE_LINE 1
#define LV_USE_IMG 1
#define LV_USE_BTN 0
#define LV_USE_BAR 0
#define LV_USE_BTNMATRIX 0
#define LV_USE_CANVAS 0
#define LV_USE_CHECKBOX 0
#define LV_USE_DROPDOWN 0
#define LV_USE_ROLLER 0
#define LV_USE_SLIDER 0
#define LV_USE_SWITCH 0
#define LV_USE_TEXTAREA 0
#define LV_USE_TABLE 0
/* extra widgets */
#define LV_USE_ANIMIMG 0
#define LV_USE_CALENDAR 0
#define LV_USE_CHART 0
#define LV_USE_COLORWHEEL 0
#define LV_USE_IMGBTN 0
#define LV_USE_KEYBOARD 0
#define LV_USE_LED 0
#define LV_USE_LIST 0
#define LV_USE_MENU 0
#define LV_USE_METER 0
#define LV_USE_MSGBOX 0
#define LV_USE_SPAN 0
#define LV_USE_SPINBOX 0
#define LV_USE_SPINNER 0
#define LV_USE_TABVIEW 0
#define LV_USE_TILEVIEW 0
#define LV_USE_WIN 0
/* themes, layouts, others */
#define LV_USE_THEME_DEFAULT 0
#define LV_USE_THEME_BASIC 0
#define LV_USE_THEME_MONO 0
#define LV_USE_FLEX 0
#define LV_USE_GRID 0
#define LV_USE_SNAPSHOT 1   /* cockpit ring background: drawn once per theme into an image (9 Nov optimisation) */
#define LV_USE_MONKEY 0
#define LV_USE_GRIDNAV 0
#define LV_USE_FRAGMENT 0
#define LV_USE_IMGFONT 0
#define LV_USE_MSG 0
#define LV_USE_IME_PINYIN 0
#define LV_USE_FS_STDIO 0
#define LV_USE_FS_POSIX 0
#define LV_USE_PNG 0
#define LV_USE_BMP 0
#define LV_USE_SJPG 0
#define LV_USE_GIF 0
#define LV_USE_QRCODE 0
#define LV_USE_FREETYPE 0
#define LV_USE_RLOTTIE 0
#define LV_USE_FFMPEG 0
#define LV_BUILD_EXAMPLES 0
#endif
