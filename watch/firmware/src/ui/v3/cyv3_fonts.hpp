#pragma once
// Cyclift Watch v3 — type scale (Deliverable A) mapped onto the generated LVGL fonts.
// Latin: Inter SemiBold / Medium with tabular figures. Arabic: Noto Sans Arabic, linked as each Latin font's fallback, so
// one label can mix Arabic words with W, bpm, rpm and digits. Large Text uses the approved larger sizes (Deliverable D v3.1).
#include <lvgl.h>

extern "C" {
extern lv_font_t cyv3_inter600_11, cyv3_inter600_12, cyv3_inter600_13, cyv3_inter600_14, cyv3_inter600_15, cyv3_inter600_17;
extern lv_font_t cyv3_inter500_11, cyv3_inter500_12, cyv3_inter500_13, cyv3_inter500_15, cyv3_inter500_20;
extern lv_font_t cyv3_digits_24, cyv3_digits_32, cyv3_digits_44, cyv3_digits_54, cyv3_digits_58;
extern lv_font_t cyv3_noto600_11, cyv3_noto600_12, cyv3_noto600_13, cyv3_noto600_14, cyv3_noto600_15, cyv3_noto600_17;
extern lv_font_t cyv3_noto400_11, cyv3_noto400_12, cyv3_noto400_13;
}

namespace cyw::v3 {

/// Typographic roles used by the Stage 1 screens. `cssSize` is the approved size in px; Inter's vertical metrics
/// (ascent 0.96875 em, descent 0.2412 em) place the baseline inside the prototype's line box.
enum class Type : uint8_t { Label, Caption, Chip, Row, RowShrink, Button, Small13, Unit, Metric24, Display32, Display44, Clock54, Display58 };

inline void linkFonts() {
    static bool done = false; if (done) return; done = true;
    cyv3_inter600_11.fallback = &cyv3_noto600_11; cyv3_inter600_12.fallback = &cyv3_noto600_12; cyv3_inter600_13.fallback = &cyv3_noto600_13;
    cyv3_inter600_14.fallback = &cyv3_noto600_14; cyv3_inter600_15.fallback = &cyv3_noto600_15; cyv3_inter600_17.fallback = &cyv3_noto600_17;
    cyv3_inter500_11.fallback = &cyv3_noto400_11; cyv3_inter500_12.fallback = &cyv3_noto400_12; cyv3_inter500_13.fallback = &cyv3_noto400_13;
}

struct Font { const lv_font_t* f; int css; int lineBox; bool tracked; };   // tracked = +0.06 em letter spacing (Latin labels)

inline Font font(Type t, bool large) {
    switch (t) {
        case Type::Label:     return large ? Font{&cyv3_inter600_14, 14, 16, true} : Font{&cyv3_inter600_12, 12, 14, true};
        case Type::Caption:   return large ? Font{&cyv3_inter500_13, 13, 16, false} : Font{&cyv3_inter500_11, 11, 13, false};
        case Type::Chip:      return {&cyv3_inter600_11, 11, 13, true};
        case Type::Row:       return large ? Font{&cyv3_inter600_17, 17, 20, false} : Font{&cyv3_inter600_15, 15, 18, false};
        case Type::RowShrink: return large ? Font{&cyv3_inter600_15, 15, 18, false} : Font{&cyv3_inter600_13, 13, 16, false};
        case Type::Button:    return large ? Font{&cyv3_inter600_17, 17, 18, false} : Font{&cyv3_inter600_15, 15, 18, false};
        case Type::Small13:   return {&cyv3_inter600_13, 13, 16, false};
        case Type::Unit:      return {&cyv3_inter500_12, 12, 14, false};
        case Type::Metric24:  return {&cyv3_digits_24, 24, 28, false};
        case Type::Display32: return {&cyv3_digits_32, 32, 32, false};
        case Type::Display44: return {&cyv3_digits_44, 44, 44, false};
        case Type::Clock54:   return {&cyv3_digits_54, 54, 58, false};
        case Type::Display58: return {&cyv3_digits_58, 58, 58, false};
    }
    return {&cyv3_inter600_12, 12, 14, false};
}

/// The unit beside a lead number is 0.34 em of the number, never below 12 px (prototype .unit rule).
inline Font unitFor(int displayPx) {
    if (displayPx >= 58) return {&cyv3_inter500_20, 20, 20, false};
    if (displayPx >= 44) return {&cyv3_inter500_15, 15, 15, false};
    return {&cyv3_inter500_12, 12, 12, false};
}

/// CSS baseline of a line box that starts at `top`: half-leading + Inter ascent.
inline int baselineOf(int top, int lineBox, int cssSize) {
    const float asc = 0.96875f, desc = 0.2412f;
    return int(top + (lineBox - (asc + desc) * cssSize) / 2.f + asc * cssSize + 0.5f);
}
/// LVGL label y that puts this font's baseline on `baseline`.
inline int labelYFor(int baseline, const lv_font_t* f) { return baseline - (f->line_height - f->base_line); }

} // namespace cyw::v3
