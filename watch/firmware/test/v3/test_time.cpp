// Stage 1.2 — computer tests for the RTC date helpers and the temporary serial time command "T<seconds>".
#include "../../src/hal/rtc_time.hpp"
#include <cstdio>
#include <cstring>
#include <string>
using namespace cyw::rtc;
static int g_fail = 0, g_n = 0;
#define CHECK(c) do { g_n++; if (!(c)) { g_fail++; std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); } } while (0)

static TimeCommand::Result run(TimeCommand& p, const std::string& s) { TimeCommand::Result r = TimeCommand::Idle; for (char c : s) r = p.feed(c); return r; }

int main() {
    // date arithmetic: every day 2024-01-01 .. 2099-12-31 at 23:59:59 round-trips through registers
    for (uint32_t t = MIN_VALID + 86399; t <= MAX_VALID; t += 86400) {
        uint8_t r[7]; toRegs(t, r); Reading x = fromRegs(r);
        if (!(x.integrity && x.t == t)) { CHECK(false); break; }
    }
    CHECK(toUnix(2026, 11, 10, 17, 30, 0) == 1794331800u);                 // 2026-11-10 17:30:00 (local)
    { int y, mo, d, h, mi, s; fromUnix(1794331800u, y, mo, d, h, mi, s); CHECK(y == 2026 && mo == 11 && d == 10 && h == 17 && mi == 30 && s == 0); }
    CHECK(weekday(1794331800u) == 2);                                       // Tuesday
    { uint8_t r[7]; toRegs(1794331800u, r); CHECK(r[0] == 0x00 && r[1] == 0x30 && r[2] == 0x17 && r[3] == 0x10 && r[4] == 2 && r[5] == 0x11 && r[6] == 0x26); }
    // integrity: VL set (power lost) → invalid; chip default after power-on (2000-01-01) → invalid
    { uint8_t r[7]; toRegs(1794331800u, r); r[0] |= 0x80; CHECK(!fromRegs(r).integrity); }
    { uint8_t r[7] = {0x80, 0, 0, 0x01, 6, 0x01, 0x00}; CHECK(!fromRegs(r).integrity); }
    { uint8_t r[7] = {0x00, 0, 0, 0x01, 6, 0x01, 0x00}; CHECK(!fromRegs(r).integrity); }     // year 2000 without VL
    { uint8_t r[7] = {0x5A, 0x7F, 0x3F, 0x3F, 7, 0x1F, 0xFF}; CHECK(!fromRegs(r).integrity); } // garbage
    // serial command parser
    { TimeCommand p; CHECK(run(p, "T1794331800\n") == TimeCommand::Done && p.value == 1794331800u && !p.active()); }
    { TimeCommand p; CHECK(run(p, "T1794331800\r") == TimeCommand::Done); }
    { TimeCommand p; CHECK(run(p, "T1794331800;") == TimeCommand::Done); }
    { TimeCommand p; CHECK(p.feed('m') == TimeCommand::Idle && p.feed('u') == TimeCommand::Idle); }   // other commands untouched
    { TimeCommand p; CHECK(p.feed('T') == TimeCommand::Busy && p.feed('1') == TimeCommand::Busy && p.active()); }  // digits are not commands
    { TimeCommand p; CHECK(run(p, "T\n") == TimeCommand::Error && !p.active()); }
    { TimeCommand p; CHECK(run(p, "T123\n") == TimeCommand::Error); }                  // before 2024
    { TimeCommand p; CHECK(run(p, "T99999999999\n") == TimeCommand::Error); }         // too many digits
    { TimeCommand p; CHECK(run(p, "T17943x") == TimeCommand::Error && !p.active() && p.feed('m') == TimeCommand::Idle); }
    { TimeCommand p; CHECK(run(p, "T4102444800\n") == TimeCommand::Error); }          // 2100
    { TimeCommand p; run(p, "T12\n"); CHECK(run(p, "T1794331800\n") == TimeCommand::Done); }   // recovers after an error
    // Milestone C (Stage 1.3): an independent calendar oracle (H. Hinnant's days-from-civil) for every day 2024-2099 —
    // leap years (2024 … 2096; 2100 is outside the valid range), month ends, the weekday, and every rollover at 23:59:59
    {
        auto civil = [](int y, int m, int d) { y -= m <= 2; int era = y / 400, yoe = y - era * 400, doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
            return era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468; };
        auto mdays = [](int y, int m) { static const int D[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}; return m == 2 && y % 4 == 0 && (y % 100 || y % 400 == 0) ? 29 : D[m - 1]; };
        int bad = 0, leap = 0, days = 0;
        for (int y = 2024; y <= 2099; y++) for (int m = 1; m <= 12; m++) for (int d = 1; d <= mdays(y, m); d++) {
            uint32_t t = uint32_t(civil(y, m, d)) * 86400u; days++; leap += m == 2 && d == 29;
            int Y, M, D, h, mi, sec; fromUnix(t + 86399, Y, M, D, h, mi, sec);
            if (toUnix(y, m, d, 0, 0, 0) != t || Y != y || M != m || D != d || h != 23 || mi != 59 || sec != 59) bad++;
            fromUnix(t + 86400, Y, M, D, h, mi, sec);                                 // one second later: the next calendar day
            int ny = y, nm = m, nd = d + 1; if (nd > mdays(y, m)) { nd = 1; if (++nm > 12) { nm = 1; ny++; } }
            if (Y != ny || M != nm || D != nd || h || mi || sec) bad++;
            int z = civil(y, m, d) + 4; if (weekday(t) != ((z % 7) + 7) % 7) bad++;   // 1970-01-01 was a Thursday (4)
        }
        CHECK(bad == 0); CHECK(days == 27759); CHECK(leap == 19);
        CHECK(toUnix(2024, 2, 29, 12, 0, 0) + 86400 == toUnix(2024, 3, 1, 12, 0, 0));
        CHECK(toUnix(2025, 2, 28, 0, 0, 0) + 86400 == toUnix(2025, 3, 1, 0, 0, 0));
        { int Y, M, D, h, mi, sec; fromUnix(toUnix(2026, 12, 31, 23, 59, 59) + 1, Y, M, D, h, mi, sec); CHECK(Y == 2027 && M == 1 && D == 1 && !h && !mi && !sec); }
        { int Y, M, D, h, mi, sec; fromUnix(MAX_VALID, Y, M, D, h, mi, sec); CHECK(Y == 2099 && M == 12 && D == 31 && h == 23 && mi == 59 && sec == 59); }
        { int Y, M, D, h, mi, sec; fromUnix(MIN_VALID, Y, M, D, h, mi, sec); CHECK(Y == 2024 && M == 1 && D == 1 && !h); }
        // the clock chip's registers across the same rollovers (the chip itself counts; this checks our read of it)
        for (uint32_t t : {toUnix(2024, 2, 28, 23, 59, 59), toUnix(2024, 2, 29, 23, 59, 59), toUnix(2025, 2, 28, 23, 59, 59), toUnix(2026, 12, 31, 23, 59, 59)}) {
            uint8_t r[7]; toRegs(t + 1, r); Reading x = fromRegs(r); CHECK(x.integrity && x.t == t + 1); }
    }
    // RC2 clock rules (owner requirements 11 Nov 20:51)
    {
        uint32_t T0 = toUnix(2026, 11, 11, 20, 0, 0);
        auto good = [](uint32_t t) { Reading r; r.t = t; r.integrity = true; return r; };
        Reading lost; lost.t = toUnix(2000, 1, 1, 0, 0, 0); lost.integrity = false;
        ClockKeeper k; CHECK(!k.valid);                                                    // nothing read yet → --:--
        k.onRead(true, lost, 0); CHECK(!k.valid);                                          // invalid RTC → --:--
        k.onRead(true, good(T0), 1000); CHECK(k.valid && k.t == T0);                       // valid RTC → time shown
        k.onRead(false, Reading{}, 11000); CHECK(k.valid && k.t == T0 + 10 && k.misses == 1);   // one missed read: last time kept, advanced
        k.onRead(false, Reading{}, 21000); CHECK(k.valid && k.t == T0 + 20);
        k.onRead(false, Reading{}, 31000); CHECK(k.valid && k.t == T0 + 30 && k.misses == 3);
        k.onRead(false, Reading{}, 41000); CHECK(!k.valid && k.invalidations == 1);       // 4th miss in a row: no longer confirmed
        k.onRead(true, good(T0 + 50), 51000); CHECK(k.valid && k.t == T0 + 50 && k.misses == 0);   // chip answers again: recovered
        k.onRead(false, Reading{}, 61000); k.onRead(true, good(T0 + 70), 71000); CHECK(k.valid && k.misses == 0);   // isolated miss: no blink
        k.onRead(true, lost, 81000); CHECK(!k.valid && k.invalidations == 2);              // genuine loss (VL): invalid at once, no stale time
        k.onRead(false, Reading{}, 91000); CHECK(!k.valid);                                 // ...and a miss after it does not bring stale time back
        k.onRead(true, good(T0 + 100), 101000); CHECK(k.valid && k.t == T0 + 100);
        { ClockKeeper w; w.onRead(true, good(T0), 0xFFFFF000u); w.onRead(false, Reading{}, 0x00002000u + 0xFFFFF000u); CHECK(w.valid && w.t == T0 + 8); }   // millis() wrap
        CHECK(k.misses_total == 6);
        // charge-status pin: 3 equal samples before the shown state changes; raw flips counted
        Debounced<3> d; CHECK(d.feed(false) == false);
        CHECK(d.feed(true) == false && d.feed(false) == false && d.feed(true) == false && d.flips == 3);   // a pin that flips: screen unchanged
        CHECK(d.feed(true) == false && d.feed(true) == true);                              // real plug-in: shown after 3 equal samples (30 s)
        CHECK(d.feed(false) == true && d.feed(false) == true && d.feed(false) == false);   // real unplug likewise
        Debounced<3> e; CHECK(e.feed(true) == true);                                       // first sample at start-up is taken as is
    }
    std::printf("time tests: %d checks, %d failed\n", g_n, g_fail);
    return g_fail ? 1 : 0;
}
