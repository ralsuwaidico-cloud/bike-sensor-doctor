#pragma once
// Cyclift Watch OS — appearance tokens: three families × dark / light (shared values with the iPhone's Checkpoint H)
// and the FIXED grading colours, which are not part of any appearance (the same table for all six).
#include <string>
#include <map>

namespace cyw::ui {

struct Appearance {
    std::string name; bool dark;
    std::map<std::string, std::string> tok;            // bg, card, card2, text, mut, line, accent, accent2, onAccent
    std::string resolve(const std::string& token) const {
        static const std::map<std::string, std::string> gradeDark = {{"grade.red", "#FF5A5A"}, {"grade.yellow", "#FFB64D"}, {"grade.blue", "#5BD0F5"}, {"grade.green", "#56E08C"}};
        static const std::map<std::string, std::string> gradeLight = {{"grade.red", "#B91C1C"}, {"grade.yellow", "#9A5A00"}, {"grade.blue", "#0E6B8C"}, {"grade.green", "#1B7A3E"}};
        if (token.rfind("grade.", 0) == 0) { auto& g = dark ? gradeDark : gradeLight; auto it = g.find(token); return it == g.end() ? "#FF00FF" : it->second; }
        auto it = tok.find(token); return it == tok.end() ? (token.size() == 7 && token[0] == '#' ? token : "#FF00FF") : it->second;
    }
};

inline const std::vector<Appearance>& appearances() {
    static const std::vector<Appearance> a = {
        {"Cyclift · Midnight Blue", true,  {{"bg", "#0A1628"}, {"card", "#122240"}, {"card2", "#1A2F55"}, {"text", "#EAF2FF"}, {"mut", "#A7BAD6"}, {"line", "#1E3357"}, {"accent", "#4FD1FF"}, {"accent2", "#9CE3FF"}, {"onAccent", "#06111A"}}},
        {"Cyclift · Arctic",        false, {{"bg", "#EEF5FB"}, {"card", "#FFFFFF"}, {"card2", "#DCE8F3"}, {"text", "#0B1A33"}, {"mut", "#3F5574"}, {"line", "#C9D8E8"}, {"accent", "#0B6E9E"}, {"accent2", "#1C8FC4"}, {"onAccent", "#FFFFFF"}}},
        {"Sport · Graphite",        true,  {{"bg", "#101214"}, {"card", "#1B1F24"}, {"card2", "#262C33"}, {"text", "#F2F4F6"}, {"mut", "#AEB6BF"}, {"line", "#2A3038"}, {"accent", "#FF6A00"}, {"accent2", "#FFB366"}, {"onAccent", "#101214"}}},
        {"Sport · Steel",           false, {{"bg", "#E9ECEF"}, {"card", "#FFFFFF"}, {"card2", "#D5DADF"}, {"text", "#111417"}, {"mut", "#454E57"}, {"line", "#C6CCD3"}, {"accent", "#B84800"}, {"accent2", "#D8732A"}, {"onAccent", "#FFFFFF"}}},
        {"Bloom · Plum",            true,  {{"bg", "#1E1024"}, {"card", "#2C1838"}, {"card2", "#3A2149"}, {"text", "#FBEFF7"}, {"mut", "#D1B4C7"}, {"line", "#432650"}, {"accent", "#FF8FB8"}, {"accent2", "#FFC3D9"}, {"onAccent", "#1E1024"}}},
        {"Bloom · Rose",            false, {{"bg", "#FBF0F5"}, {"card", "#FFFFFF"}, {"card2", "#F0DCE7"}, {"text", "#2A1230"}, {"mut", "#634A5C"}, {"line", "#EBCFDD"}, {"accent", "#A82B64"}, {"accent2", "#D45A90"}, {"onAccent", "#FFFFFF"}}},
    };
    return a;
}

} // namespace cyw::ui
