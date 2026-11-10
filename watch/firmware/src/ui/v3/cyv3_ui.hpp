#pragma once
// Cyclift Watch v3 — Stage 1 LVGL screens: Orbit face, app menu, cycling cockpit (Obsidian theme; Standard, Focused and
// Large Text; English and Arabic). Screen objects are kept alive: a screen is rebuilt only when its structure changes
// (screen, settings, workout state, connection, sensors present, overlays); live values are updated in place, so LVGL
// redraws only the areas that changed.
#include <lvgl.h>
#include <array>
#include <string>
#include <unordered_map>
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
    /// Everything that changes the screen's structure (see structureKey); compared every frame, so plain integers.
    using Key = std::array<int, 32>;
    Key key_{}; bool keyValid_ = false;
    std::vector<HitArea> hits_;
    const Palette* pal_ = nullptr;
    bool large_ = false, ar_ = false;
    // retained handles for in-place updates
    Run clock_, date_, interval_, lead_, hrTile_, cadTile_;
    lv_obj_t *cmd_ = nullptr, *marker_ = nullptr, *ivArc_ = nullptr;
    int cmdTop_ = 0, leadPx_ = 0;
    std::vector<std::vector<lv_point_t>> lines_;   // point storage for lv_line objects (must outlive them)
    std::vector<std::vector<lv_obj_t*>> groups_;   // objects that are read together (a run, or a tile's number + caption): hidden together
    /// The text each label was last given, as the UI wrote it. LVGL keeps a reshaped copy of Arabic text, so comparing a new
    /// value with lv_label_get_text() never matches in Arabic and made every update rewrite (and redraw) the label (fix 9 Nov).
    std::unordered_map<const lv_obj_t*, std::string> src_;
    /// Sets the label's text only when it differs from what was last set; returns true when it changed.
    bool setText(lv_obj_t* l, const std::string& s);
    /// Gives the label `s`: text without Arabic letters is kept by reference in src_ (lv_label_set_text_static), so LVGL
    /// skips its Arabic-shaping scan of every character; Arabic text is copied and shaped by LVGL as before.
    void putText(lv_obj_t* l, const std::string& s);
    /// LONG_DOT labels: LVGL writes the dots into the label's own text, so they always get a private copy.
    void dotMode(lv_obj_t* l);
    /// Ring arcs skip drawing an area that lies wholly inside their inner edge (they have no pixels there).
    static void ringSkip(lv_obj_t* arc, int innerRadius);

    Key structureKey(const Model& m) const;
    void build(const Model& m);
    void update(const Model& m);
    void buildFace(const Model& m);
    void buildMenu(const Model& m);
    void buildCockpit(const Model& m);
    // Stage 1.3 screens (prototype screens1.js)
    void buildToday(const Model& m);
    void buildWeek(const Model& m);
    void buildQuick(const Model& m);
    void buildWHealth(const Model& m);
    void buildWCoach(const Model& m);
    void buildWActivity(const Model& m);
    void buildNotYet(const Model& m);
    void updateToday(const Model& m);
    // Stage 1.3 primitives
    /// Section header (prototype hdr): uppercase label at y 24 (26 in Large Text), optional caption under it at y 38 (44).
    void header(const std::string& title, const std::string& sub);
    /// One centred line of text whose line box starts at `top`; returns the label.
    lv_obj_t* textLine(int top, const std::string& s, const Font& f, uint32_t color, int centerX = 120);
    /// Wrapped paragraph `width` px wide starting at x `left`; `center` centres each line.
    lv_obj_t* paragraph(int top, int left, int width, const std::string& s, const Font& f, int lineH, uint32_t color, bool center);
    void icon(int top, const lv_img_dsc_t* ic, uint32_t color, int centerX = 120);
    /// Page dots (prototype pdots): n dots, the current one a 12 px pill.
    void pageDots(int n, int index, int top);
    /// Prototype emptyState(): 28 px icon, title, caption.
    void emptyState(const lv_img_dsc_t* ic, const std::string& title, const std::string& sub);
    lv_obj_t* bikeButton(int top, const std::string& text, int kind, Action a);
    Run bikeInfo_;                               // Bike Mode: 'WATTS · 152 bpm' line under the 76 px number
    /// The cockpit ring parts that never change during a ride (track, target band, zone ticks, interval track).
    void staticRing();
    /// Draws staticRing() once per theme into an opaque image (LVGL snapshot, pixel-identical) and places it as the
    /// cockpit background, so 1 Hz updates copy ring pixels instead of re-drawing five anti-aliased arcs. Returns false
    /// (and the arcs are created as objects, as before) if the image buffer cannot be allocated.
    bool ringBackground();
    lv_obj_t* ringImg_ = nullptr;
    void buildOverlays(const Model& m);
    void hideUnder(lv_obj_t* overlay, int margin);
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
    /// Key 2 chip: the prototype's y 150; in Large Text 138 so it stays above the taller button (168).
    int keyChipTop() const { return large_ ? 138 : 150; }
};

} // namespace cyw::v3
