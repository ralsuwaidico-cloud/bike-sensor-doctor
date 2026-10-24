/*
 * Device user interface for the round 240 x 240 screen. Uses only LVGL, app.h and plat.h, so it renders identically
 * on the PC test harness (test/sim) where every screen is checked against the visible circle.
 *
 * Round-screen rules (enforced by test/sim):
 *  - all text and controls stay inside a circle of radius UI_SAFE_R around the centre;
 *  - near the top and bottom the usable width shrinks (ui_chord); short labels, big numbers;
 *  - ASCII text only in the label fonts (no typographic dashes/dots that the fonts lack);
 *  - never pass %f to lv_*_fmt (LVGL printf has no float support) — use snprintf.
 */
#pragma once
#include <stdbool.h>
#include "lvgl.h"
#include "app.h"
#include "app_power.h"

#ifdef __cplusplus
extern "C" {
#endif

#define UI_W 240
#define UI_R 120
#define UI_SAFE_R 115

#define C_BG     lv_color_hex(0x05080A)
#define C_PANEL  lv_color_hex(0x121A1F)
#define C_TRACK  lv_color_hex(0x1C272D)
#define C_FG     lv_color_hex(0xEAF2F4)
#define C_MUT    lv_color_hex(0x8494A0)
#define C_FAINT  lv_color_hex(0x3A4850)
#define C_CYAN   lv_color_hex(0x34E7E4)
#define C_GREEN  lv_color_hex(0x56E08C)
#define C_AMBER  lv_color_hex(0xFFB64D)
#define C_RED    lv_color_hex(0xFF5A5A)
#define C_VIOLET lv_color_hex(0xA996FF)
#define C_DEMO   lv_color_hex(0xFF8A1F)
#define C_INK    lv_color_hex(0x05110F)

LV_FONT_DECLARE(bc_num80)
LV_FONT_DECLARE(bc_num60)
LV_FONT_DECLARE(bc_num44)
LV_FONT_DECLARE(bc_bold22)
LV_FONT_DECLARE(bc_bold16)

typedef enum {
    UI_SCR_ONBOARD = 0, UI_SCR_HOME, UI_SCR_RIDE, UI_SCR_RESULTS, UI_SCR_HISTORY, UI_SCR_SETTINGS, UI_SCR_SENSORS,
    UI_SCR_DIAG, UI_SCR_OTHER
} ui_scr_t;

/* start-up: shows onboarding, a recovered-ride notice, or Home */
void ui_start(void);

/* screen management */
typedef void (*ui_update_cb_t)(void);
lv_obj_t *ui_screen_new(ui_scr_t kind, ui_update_cb_t update);
void ui_screen_show(lv_obj_t *scr);
ui_scr_t ui_current(void);

/* geometry */
int ui_chord(int y);                  /* half-width of the safe circle at row y */

/* building blocks */
lv_obj_t *ui_label(lv_obj_t *p, const lv_font_t *f, lv_color_t c, const char *txt);
lv_obj_t *ui_title(lv_obj_t *p, const char *txt);                      /* small cyan heading at the top */
lv_obj_t *ui_pill(lv_obj_t *p, const char *txt, lv_color_t bg, lv_color_t fg, int w, int h, lv_event_cb_t cb, void *ud);
lv_obj_t *ui_round_btn(lv_obj_t *p, const char *sym, lv_color_t bg, lv_color_t fg, int d, lv_event_cb_t cb, void *ud);
/* bottom navigation: optional back button + main action pill */
void ui_nav(lv_obj_t *p, lv_event_cb_t back, const char *next_txt, lv_event_cb_t next, void *ud);
/* a button that must be held for hold_ms (progress ring) before cb fires — for Pause/End/Delete */
lv_obj_t *ui_hold_btn(lv_obj_t *p, const char *txt, lv_color_t bg, lv_color_t fg, int w, int h, uint32_t hold_ms, lv_event_cb_t cb, void *ud);
/* a vertically scrolling area kept inside the circle (y0..y1) */
lv_obj_t *ui_scroll_area(lv_obj_t *p, int y0, int y1);
/* a centred column of rows inside a scroll area */
lv_obj_t *ui_row_btn(lv_obj_t *list, const char *left, const char *right, lv_color_t right_c, lv_event_cb_t cb, void *ud);
/* roller ("spinning wheel") */
lv_obj_t *ui_wheel(lv_obj_t *p, const char *options, int sel, int w, int rows, const lv_font_t *f);
void ui_page_dots(lv_obj_t *p, int n, int active, int y);

/* the orange DEMO badge on every screen while demo mode is on */
void ui_demo_badge_refresh(void);
void ui_demo_badge_hide_for_screen(bool hide);

/* short status helpers */
const char *ui_link_text(plat_link_t l);
lv_color_t ui_link_color(plat_link_t l);
lv_color_t ui_level_color(bc_cue_level_t l);
unsigned ui_hex(lv_color_t c);                         /* 0xRRGGBB for LVGL recolor text */
const char *ui_cue_short(const bc_cue_t *c);
void ui_battery_text(char *buf, size_t cap);

/* screens */
void ui_onboard_start(void);
void ui_home_show(void);
void ui_ride_show(void);
void ui_results_show(const bc_ride_summary_t *s, bool fresh);   /* fresh = just ended, offers save/discard */
void ui_history_show(bool demo);
void ui_settings_show(void);
void ui_sensors_show(void);
void ui_diag_show(void);
void ui_pair_show(plat_sens_kind_t kind, bool onboarding);
void ui_recovered_show(const bc_ride_summary_t *s);
/* single-value editors used by onboarding and Settings */
typedef enum { UI_EDIT_NAME = 0, UI_EDIT_AGE, UI_EDIT_WEIGHT, UI_EDIT_HEIGHT, UI_EDIT_EXP, UI_EDIT_GOAL, UI_EDIT_FTP, UI_EDIT_MAXHR,
               UI_EDIT_STYLE, UI_EDIT_BRIGHT, UI_EDIT_WIFI } ui_edit_t;
void ui_edit_show(ui_edit_t what, bool onboarding);

/* ride-screen designs (visual alternatives over the same data and coaching) */
typedef struct { char letter; const char *name, *hint; void (*build)(lv_obj_t *tile); bool cad_inline; } ui_ride_design_t;
int ui_ride_design_count(void);
const ui_ride_design_t *ui_ride_design(int i);
const lv_image_dsc_t *ui_ride_thumb(int i);     /* preview picture, NULL if none */
void ui_display_show(void);
void ui_style_picker_show(void);
void ui_sensor_test_show(bool from_diag);
void ui_health_show(void);
void ui_diag_menu_show(void);
void ui_wifi_show(void);
void ui_phone_show(void);
void ui_passkey_refresh(void);   /* pairing-code pop-up on any screen */

/* power (0.5.0): Quick Settings over any screen, screen-off/lock shield, Power settings page */
void ui_power_init(void);                 /* once at ui_start (re-run after a simulated restart) */
void ui_power_refresh(void);              /* from the 250 ms UI timer */
void ui_power_attach_screen(lv_obj_t *scr, ui_scr_t kind);   /* top-edge swipe-down opens Quick Settings on non-ride screens */
void ui_power_gesture(lv_dir_t d);
void ui_qs_open(void);
void ui_qs_close(void);
bool ui_qs_is_open(void);
void ui_power_settings_show(void);

/* test hooks */
void ui_test_set_style(int style);

#ifdef __cplusplus
}
#endif
