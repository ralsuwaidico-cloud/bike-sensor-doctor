#pragma once
// Cyclift Watch OS — the fixed four-colour performance grading shared with the iPhone (Checkpoint H, owner 8 Nov):
// Red critical · Yellow caution · LightBlue on target · Green excellent. Theme-independent: these are NOT theme tokens.
// Metric-specific rules, never a grade for missing data, every grade carries text + an icon name (never colour alone).
#include <cstdint>
#include <optional>

namespace cyw {

enum class Grade : uint8_t { Red, Yellow, LightBlue, Green };

struct GradeStyle { uint16_t rgb565Dark; uint16_t rgb565Light; const char* text; const char* icon; };

/// RGB565 values for the dark and light canvases (from the iPhone spec: #FF5A5A/#B91C1C, #FFB64D/#9A5A00,
/// #5BD0F5/#0E6B8C, #56E08C/#1B7A3E). Identical in all six appearances by construction — there is one table.
inline const GradeStyle& style(Grade g) {
    static const GradeStyle t[4] = {
        {0xFAEB, 0xB8E3, "far off",   "warning"},
        {0xFDA9, 0x9AC0, "adjust",    "caution"},
        {0x5E9E, 0x0B51, "on target", "check"},
        {0x570F, 0x1BC7, "achieved",  "star"},
    };
    return t[uint8_t(g)];
}

/// Power or heart rate against a target band [lo, hi]: inside → on target; within 5 % of the band width outside →
/// caution; further → critical. `achieved` is decided by the caller at step end (≥ 90 % of the step inside the band).
inline std::optional<Grade> gradeAgainstBand(std::optional<float> value, float lo, float hi) {
    if (!value || hi <= lo) return std::nullopt;                 // no reading or no target → NO grade
    float v = *value, margin = 0.05f * (hi - lo);
    if (v >= lo && v <= hi) return Grade::LightBlue;
    if (v >= lo - margin && v <= hi + margin) return Grade::Yellow;
    return Grade::Red;
}
/// Step summary: share of the step spent in band.
inline std::optional<Grade> gradeStep(std::optional<float> inBandShare, bool cutShort) {
    if (!inBandShare) return std::nullopt;
    if (cutShort) return Grade::Red;
    if (*inBandShare >= 0.90f) return Grade::Green;
    if (*inBandShare >= 0.60f) return Grade::LightBlue;
    if (*inBandShare >= 0.30f) return Grade::Yellow;
    return Grade::Red;
}
/// Cadence against a preferred range: no Green (there is no "goal" in cadence).
inline std::optional<Grade> gradeCadence(std::optional<float> rpm, float lo, float hi) {
    if (!rpm || hi <= lo) return std::nullopt;
    if (*rpm >= lo && *rpm <= hi) return Grade::LightBlue;
    if (*rpm >= lo - 5 && *rpm <= hi + 5) return Grade::Yellow;
    return Grade::Red;
}
/// Weekly plan adherence (planned minutes done / planned).
inline std::optional<Grade> gradeAdherence(std::optional<float> share) {
    if (!share) return std::nullopt;
    if (*share >= 0.90f) return Grade::Green;
    if (*share >= 0.70f) return Grade::LightBlue;
    if (*share >= 0.50f) return Grade::Yellow;
    return Grade::Red;
}

} // namespace cyw
