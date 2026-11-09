#pragma once
// Cyclift Watch v3 — Stage 1 LVGL screens: Orbit face, app menu, cycling cockpit (Obsidian theme; Standard, Focused and
// Large Text; English and Arabic). Screen objects are kept alive: a screen is rebuilt only when its structure changes
// (screen, settings, workout state, connection, sensors present, overlays); live values are updated in place, so LVGL
// redraws only the areas that changed.
#include <lvgl.h>
#include <string>
#include <vector>
#include "cyv3_model.hpp"
#include "cyv3_fonts.hpp"

namespace cyw::v3 {

struct HitArea { lv_area_t area; Action action; int arg; const char* name; };

/// One horizontal run of text pieces, dots and icons that share a baseline (e.g. "SUN 8 NOV  64%").
struct Piece {
    enum Kind : uint8_t { Text, Dot, RingDot, Icon } kind = Text;
    std::string text; Font font{}; uint32_t color = 0; int gapBefore = 0; const lv_img_dsc_t* icon = nullptr; int iconDrop = 0;
    bool rtlText = false;                       // Arabic text piece (LVGL shapes and orders it right-to-left)
    lv_obj_t* obj = nullptr;
};
struct Run { std::vector<Piece> pieces; int top = 0, lineBox = 0, mainCss = 0; int centerX = 120; bool reverse = false; int width = 0; };

class Ui {
public:
    void begin(lv_obj_t* root);
    /// Draws the model: rebuild when the structure changed, otherwise update values in place. Returns true on rebuild.
    bool render(const Model& m);
    /// Touch → action. Returns true when a hit area was found.
    bool tap(Model& m, int x, int y, uint32_t now);
    const std::vector<HitArea>& hits() const { return hits_; }
    lv_obj_t* root() const { return root_; }
    uint32_t rebuilds = 0, updates = 0;
    /// Font chosen for the lead number on the last render (58, 44 or 32 px; 0 = did not fit).
    int leadPx() const { return leadPx_; }

private:
    lv_obj_t* root_ = nullptr;
    std::string key_;
    std::vector<HitArea> hits_;
    const Palette* pal_ = nullptr;
    bool large_ = false, ar_ = false;
    // retained handles for in-place updates
    Run clock_, date_, interval_, lead_, hrTile_, cadTile_;
    lv_obj_t *cmd_ = nullptr, *marker_ = nullptr, *ivArc_ = nullptr;
    int cmdTop_ = 0, leadPx_ = 0;
    std::vector<std::vector<lv_point_t>> lines_;   // point storage for lv_line objects (must outlive them)

    std::string structureKey(const Model& m) const;
    void build(const Model& m);
    void update(const Model& m);
    void buildFace(const Model& m);
    void buildMenu(const Model& m);
    void buildCockpit(const Model& m);
    void buildOverlays(const Model& m);
    void updateFace(const Model& m);
    void updateCockpit(const Model& m);

    // primitives
    lv_obj_t* label(lv_obj_t* parent, const std::string& s, const Font& f, uint32_t color, bool rtlText);
    void layoutRun(Run& r);
    void makeRun(Run& r);
    lv_obj_t* arc(int r, int width, float a0, float a1, uint32_t color, lv_opa_t opa = LV_OPA_COVER);
    lv_obj_t* line(std::vector<lv_point_t> pts, int width, uint32_t color);
    lv_obj_t* chip(int top, const std::string& text, uint32_t color, int dot, uint32_t bg, int outline = 0);   // dot: 0 none, 1 filled, 2 ring
    lv_obj_t* button(int top, const std::string& text, int kind, Action a);   // kind: 0 secondary, 1 primary, 2 loading
    void hit(int x, int y, int w, int h, Action a, int arg, const char* name);
    void setLead(const Model& m);
    void setTile(Run& r, int v, const char* unit);
    void setCommand(const Model& m);
    void placeMarker(const Model& m);
};

} // namespace cyw::v3
