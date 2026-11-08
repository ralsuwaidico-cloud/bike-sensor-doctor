// Renders every primary screen × six appearances × text variants to SVG and runs the round-display checks.
// Usage: ./gallery <outdir>   → writes <outdir>/<variant>/<appearance>/<screen>.svg and <outdir>/REPORT.md; exit 1 on findings.
#include "../../src/domain/screens.hpp"
#include "../../src/domain/layout_checks.hpp"
#include "../../src/domain/render_svg.hpp"
#include <fstream>
#include <cstdio>
#include <sys/stat.h>
using namespace cyw::ui;
static std::string slug(std::string s) { for (auto& c : s) if (!isalnum((unsigned char)c)) c = '-'; return s; }
int main(int argc, char** argv) {
    std::string out = argc > 1 ? argv[1] : "gallery-out"; mkdir(out.c_str(), 0755);
    HostMeasurer m; std::vector<Finding> all; int scenes = 0;
    std::ofstream rep(out + "/REPORT.md"); rep << "# Round-display checks\n\n";
    for (auto& [vname, content] : contentVariants()) {
        mkdir((out + "/" + vname).c_str(), 0755);
        for (auto& ap : appearances()) {
            std::string dir = out + "/" + vname + "/" + slug(ap.name); mkdir(dir.c_str(), 0755);
            for (auto& sc : allScreens(m, content)) {
                scenes++;
                std::ofstream f(dir + "/" + slug(sc.name) + ".svg"); f << toSvg(sc, ap, m, false);
                auto fs = check(sc, ap, vname); all.insert(all.end(), fs.begin(), fs.end());
            }
        }
    }
    // measured text sizes per screen (long variant): min / max font per role, in px and in mm on the 32.5 mm panel
    { std::ofstream tx(out + "/TEXT_SIZES.md"); tx << "# Measured text sizes (long-text variant, host measurer)\n\nPanel 1.28\" = 32.5 mm across 240 px → 0.135 mm/px; a lower-case x-height is ≈ 0.52 × font.\n\n| screen | smallest label | smallest body | largest value | elements |\n|---|---|---|---|---|\n";
      Content longC; for (auto& [vn, c] : contentVariants()) if (vn == "long") longC = c;
      for (auto& sc : allScreens(m, longC)) { float minL = 1e9, minB = 1e9, maxV = 0; int n = 0; for (auto& e : sc.els) if (e.kind == Kind::Text) { n++; if (e.role == Role::Label || e.role == Role::Unit) minL = std::min(minL, e.font); if (e.role == Role::Body || e.role == Role::Comp || e.role == Role::Button) minB = std::min(minB, e.font); if (e.role == Role::Value) maxV = std::max(maxV, e.font); }
        auto mm = [](float px) { char b[32]; std::snprintf(b, sizeof b, "%.0f px (%.1f mm)", px, px * 0.135f); return std::string(b); };
        tx << "| " << sc.name << " | " << (minL < 1e8 ? mm(minL) : "—") << " | " << (minB < 1e8 ? mm(minB) : "—") << " | " << (maxV > 0 ? mm(maxV) : "—") << " | " << n << " |\n"; } }
    rep << scenes << " scenes checked (" << contentVariants().size() << " text variants × " << appearances().size() << " appearances × " << allScreens(m, Content{}).size() << " screens)\n\n";
    rep << (all.empty() ? "**All checks passed.**\n" : "## Findings\n\n| screen | appearance | variant | rule | detail |\n|---|---|---|---|---|\n");
    for (auto& f : all) rep << "| " << f.screen << " | " << f.theme << " | " << f.variant << " | " << f.rule << " | " << f.detail << " |\n";
    std::printf("%d scenes, %zu findings\n", scenes, all.size());
    for (auto& f : all) std::printf("  [%s] %s · %s · %s: %s\n", f.rule.c_str(), f.screen.c_str(), f.theme.c_str(), f.variant.c_str(), f.detail.c_str());
    return all.empty() ? 0 : 1;
}
