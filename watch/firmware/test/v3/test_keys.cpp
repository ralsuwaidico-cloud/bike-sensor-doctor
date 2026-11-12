// Button decoder tests (cyv3_keys.hpp): debounce, short / hold / hold2, L1+L2 chord with cancellation, determinism.
#include "../../src/ui/v3/cyv3_keys.hpp"
#include <cstdio>
#include <string>
#include <vector>
using namespace cyw::v3;

static int g_checks = 0, g_fail = 0;
#define CHECK(c, ...) do { g_checks++; if (!(c)) { g_fail++; std::printf("FAIL %s:%d: ", __FILE__, __LINE__); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

struct Sim {
    KeyDecoder d; uint32_t t = 1000; bool l1 = false, l2 = false, r2 = false; std::vector<KeyEvent> ev;
    void run(uint32_t ms) { for (uint32_t i = 0; i < ms; i += 10) { t += 10; KeyEvent e[8]; int n = d.feed(l1, l2, r2, t, e); for (int k = 0; k < n; k++) if (e[k].ev != KeyEv::ChordTick) ev.push_back(e[k]); } }
    std::string str() const {
        static const char* E[] = {"-", "short", "hold", "hold2", "chord", "tick", "cancel", "fire"}; static const char* B[] = {"L1", "L2", "R2"};
        std::string s; for (auto& e : ev) { if (!s.empty()) s += ' '; s += E[int(e.ev)]; if (e.ev <= KeyEv::Hold2) { s += ':'; s += B[int(e.btn)]; } } return s;
    }
};

int main() {
    { Sim s; s.l1 = true; s.run(100); s.l1 = false; s.run(100); CHECK(s.str() == "short:L1", "short L1: %s", s.str().c_str()); }
    { Sim s; s.l2 = true; s.run(20); s.l2 = false; s.run(100); CHECK(s.str() == "", "20 ms blip ignored: %s", s.str().c_str()); }
    { Sim s; for (int i = 0; i < 4; i++) { s.l2 = true; s.run(10); s.l2 = false; s.run(10); } s.l2 = true; s.run(200); s.l2 = false; s.run(100);
      CHECK(s.str() == "short:L2", "contact bounce gives one press: %s", s.str().c_str()); }
    { Sim s; s.r2 = true; s.run(1100); CHECK(s.str() == "hold:R2", "R2 hold at 1 s: %s", s.str().c_str()); s.r2 = false; s.run(100);
      CHECK(s.str() == "hold:R2", "no short after a hold: %s", s.str().c_str()); }
    { Sim s; s.l1 = true; s.run(2100); s.l1 = false; s.run(100); CHECK(s.str() == "hold:L1 hold2:L1", "L1 hold then hold2: %s", s.str().c_str()); }
    { Sim s; s.l1 = true; s.run(1500); s.l1 = false; s.run(100); CHECK(s.str() == "hold:L1", "L1 released at 1.5 s: hold only: %s", s.str().c_str()); }
    { Sim s; s.l2 = true; s.run(990); s.l2 = false; s.run(100); CHECK(s.str() == "short:L2", "0.99 s still short: %s", s.str().c_str()); }
    // two-press: two clean shorts
    { Sim s; s.l2 = true; s.run(100); s.l2 = false; s.run(400); s.l2 = true; s.run(100); s.l2 = false; s.run(100); CHECK(s.str() == "short:L2 short:L2", "two presses: %s", s.str().c_str()); }
    // chord: full 10 s
    { Sim s; s.l1 = true; s.run(200); s.l2 = true; s.run(10200); CHECK(s.str() == "chord fire", "chord fires at 10 s: %s", s.str().c_str());
      s.l1 = false; s.run(100); s.l2 = false; s.run(100); CHECK(s.str() == "chord fire", "nothing after fire: %s", s.str().c_str()); }
    // chord: cancelled by releasing L2 early; L1 still held → no hold / short for L1 afterwards
    { Sim s; s.l1 = true; s.l2 = true; s.run(4000); s.l2 = false; s.run(2000); s.l1 = false; s.run(100);
      CHECK(s.str() == "chord cancel", "early release cancels, nothing else fires: %s", s.str().c_str()); }
    // chord at 9.9 s released → cancel, never fire
    { Sim s; s.l1 = true; s.l2 = true; s.run(9950); s.l1 = false; s.run(100); s.l2 = false; s.run(50);
      CHECK(s.str() == "chord cancel", "9.95 s → cancel: %s", s.str().c_str()); }
    // second button > 1 s later → no chord (the first one's hold already fired)
    { Sim s; s.l1 = true; s.run(1200); s.l2 = true; s.run(3000); s.l2 = false; s.l1 = false; s.run(100);
      CHECK(s.str() == "hold:L1 hold2:L1 hold:L2", "late second button is not a chord: %s", s.str().c_str()); }
    // brief overlap (< 150 ms) of L1 and L2: neither short fires (ambiguous)
    { Sim s; s.l1 = true; s.run(100); s.l2 = true; s.run(80); s.l1 = false; s.run(50); s.l2 = false; s.run(100);
      CHECK(s.str() == "", "ambiguous overlap gives nothing: %s", s.str().c_str()); }
    // R2 is independent of the chord; L2 + R2 together are two separate inputs
    { Sim s; s.l2 = true; s.r2 = true; s.run(300); s.l2 = false; s.r2 = false; s.run(100); CHECK(s.str() == "short:L2 short:R2" || s.str() == "short:R2 short:L2", "L2+R2 are not a chord: %s", s.str().c_str()); }
    { Sim s; s.l1 = true; s.l2 = true; s.r2 = true; s.run(10200); s.l1 = s.l2 = s.r2 = false; s.run(100);
      CHECK(s.str() == "chord hold:R2 fire" || s.str() == "hold:R2 chord fire" || s.str() == "chord fire hold:R2" , "R2 held during the chord keeps its own hold: %s", s.str().c_str()); }
    // heldMs for the ring
    { Sim s; s.l1 = true; s.run(700); CHECK(s.d.heldMs(Btn::L1, s.t) >= 650 && s.d.heldMs(Btn::L1, s.t) <= 700, "heldMs %u", unsigned(s.d.heldMs(Btn::L1, s.t))); }
    // determinism: the same input sequence always gives the same events (random soak, replayed)
    {
        auto runSeq = [](uint32_t seed) { Sim s; uint32_t r = seed; for (int i = 0; i < 4000; i++) { r = r * 1103515245u + 12345u;
            int b = (r >> 8) % 7; if (b == 0) s.l1 = !s.l1; else if (b == 1) s.l2 = !s.l2; else if (b == 2) s.r2 = !s.r2; s.run(10 + (r >> 16) % 400); } s.l1 = s.l2 = s.r2 = false; s.run(200); return s.str(); };
        CHECK(runSeq(7) == runSeq(7), "deterministic");
        // invariant: never a short press of a button while its hold was reported for the same press → checked inside the decoder
        int fires = 0; for (uint32_t seed = 1; seed < 200; seed++) { std::string x = runSeq(seed); if (x.find("fire") != std::string::npos) fires++; }
        std::printf("keys soak: 199 random sequences, %d reached a restart\n", fires);
    }
    std::printf("key tests: %d checks, %d failures\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
