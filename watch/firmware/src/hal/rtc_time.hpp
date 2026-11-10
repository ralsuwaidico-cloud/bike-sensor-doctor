#pragma once
// Pure date/time helpers for the PCF8563 real-time clock and the temporary serial time command (Stage 1.2).
// No Arduino dependency: compiled on the computer by test/v3/test_time.cpp and on the watch by hal/esp32/drivers.hpp.
//
// The watch keeps LOCAL wall-clock time in the RTC. In the approved architecture the iPhone sets it over Bluetooth
// (Stage 4); until then the temporary serial command "T<seconds>" (local time as seconds since 1970-01-01 00:00) lets the
// PC set it for testing. Both paths write the same RTC; nothing else depends on who set it.
#include <cstdint>

namespace cyw::rtc {

inline uint8_t bcd(uint8_t v) { return uint8_t((v >> 4) * 10 + (v & 0x0F)); }
inline uint8_t enc(int v) { return uint8_t(((v / 10) << 4) | (v % 10)); }

inline uint32_t toUnix(int y, int mo, int d, int h, int mi, int s) {
    int a = (14 - mo) / 12, yy = y + 4800 - a, mm = mo + 12 * a - 3;
    long jdn = d + (153 * mm + 2) / 5 + 365L * yy + yy / 4 - yy / 100 + yy / 400 - 32045;
    return uint32_t((jdn - 2440588L) * 86400L + h * 3600 + mi * 60 + s);
}

inline void fromUnix(uint32_t t, int& y, int& mo, int& d, int& h, int& mi, int& s) {
    long days = t / 86400; long rem = t % 86400; h = int(rem / 3600); mi = int((rem % 3600) / 60); s = int(rem % 60);
    long z = days + 719468; long era = (z >= 0 ? z : z - 146096) / 146097; unsigned doe = unsigned(z - era * 146097);
    unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; long yr = long(yoe) + era * 400;
    unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100); unsigned mp = (5 * doy + 2) / 153;
    d = int(doy - (153 * mp + 2) / 5 + 1); mo = int(mp < 10 ? mp + 3 : mp - 9); y = int(yr + (mo <= 2));
}

inline int weekday(uint32_t t) { return int(((t / 86400) + 4) % 7); }   // 0 = Sunday; 1970-01-01 was a Thursday

/// The 7 PCF8563 time registers (0x02..0x08) for `t`. Seconds bit 7 (VL, "clock integrity lost") is written as 0.
inline void toRegs(uint32_t t, uint8_t r[7]) {
    int y, mo, d, h, mi, s; fromUnix(t, y, mo, d, h, mi, s);
    r[0] = enc(s); r[1] = enc(mi); r[2] = enc(h); r[3] = enc(d); r[4] = uint8_t(weekday(t)); r[5] = enc(mo); r[6] = enc(y - 2000);
}

struct Reading { uint32_t t = 0; bool integrity = false; };
/// Decodes the 7 registers. integrity is false when the chip reports VL (it lost power since it was last set) or the
/// date is outside 2024..2099 — the face then shows "--:--" instead of a wrong time.
inline Reading fromRegs(const uint8_t r[7]) {
    Reading out;
    bool vl = (r[0] & 0x80) != 0;
    int s = bcd(r[0] & 0x7F), mi = bcd(r[1] & 0x7F), h = bcd(r[2] & 0x3F), d = bcd(r[3] & 0x3F), mo = bcd(r[5] & 0x1F), y = 2000 + bcd(r[6]);
    bool sane = s < 60 && mi < 60 && h < 24 && d >= 1 && d <= 31 && mo >= 1 && mo <= 12 && y >= 2024;
    out.t = sane ? toUnix(y, mo, d, h, mi, s) : 0;
    out.integrity = sane && !vl;
    return out;
}

constexpr uint32_t MIN_VALID = 1704067200u;   // 2024-01-01 00:00
constexpr uint32_t MAX_VALID = 4102444799u;   // 2099-12-31 23:59:59

/// Temporary serial command "T<digits>" ended by newline, CR, ';' or space. Feed every received character; after 'T' the
/// parser owns the digits, so they are not taken as other one-letter commands. Returns Done (value in `value`), Error, or
/// Busy (characters consumed), Idle (character not for this parser).
class TimeCommand {
public:
    enum Result { Idle, Busy, Done, Error };
    Result feed(char c) {
        if (!active_) { if (c != 'T') return Idle; active_ = true; digits_ = 0; value = 0; return Busy; }
        if (c >= '0' && c <= '9') {                     // more than 10 digits: keep consuming, report at the end
            if (++digits_ <= 10) value = value * 10 + uint64_t(c - '0');
            return Busy;
        }
        active_ = false;
        bool end = c == '\n' || c == '\r' || c == ';' || c == ' ';
        if (!end || digits_ == 0 || digits_ > 10 || value < MIN_VALID || value > MAX_VALID) return Error;
        return Done;
    }
    bool active() const { return active_; }
    uint64_t value = 0;
private:
    bool active_ = false; int digits_ = 0;
};

}  // namespace cyw::rtc
