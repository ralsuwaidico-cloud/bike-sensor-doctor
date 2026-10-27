/*
 * 0.7.4 start-up failure test: the REAL main/ble_central.c + main/ble_link.c on the fake NimBLE, with nimble_port_init()
 * failing exactly like the owner's board on 27 Oct ("BLE_INIT: hci inits failed" -> ESP_FAIL), and with the NimBLE host task
 * that cannot be created. 0.7.3 aborted (ESP_ERROR_CHECK). Now: no abort, Bluetooth reported unavailable with the reason and
 * the heap figures, every API the UI / app call afterwards is safe, and the phone link reports PLAT_PHONE_UNAVAILABLE.
 * Exit 0 = all checks passed (built with ASan + UBSan).
 */
#include "fake_nimble.h"
#include "ble_central.h"
#include "ble_link.h"
#include "plat.h"
#include <unistd.h>

void app_psvc_on_disconnect(void) {}
bool plat_device_id(uint8_t out[6]) { memset(out, 0xAB, 6); return true; }
void ble_store_config_init(void) {}
/* device: diag_esp.c (Bluetooth unavailable = the boot plan disabled it, or the stack did not start) */
bool plat_bt_unavailable(char *reason, size_t cap) { if (!ble_central_unavailable()) return false; if (reason && cap) snprintf(reason, cap, "%s", ble_central_init_info()->reason); return true; }

static int checks, fails;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)
static const uint8_t MAC[6] = { 1, 2, 3, 4, 5, 6 };

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    int mode = argc > 1 ? atoi(argv[1]) : 0;   /* 0: HCI init fails, 1: host task cannot be created */
    if (mode == 0) { g_fake_nimble_init_err = ESP_FAIL; g_fake_heap_free = 21000; g_fake_heap_largest = 7400; }
    else g_fake_fail_task = "nimble_host";
    bool stack = ble_central_stack_init();
    bool up = ble_central_start(false);
    const ble_central_init_t *in = ble_central_init_info();
    if (mode == 0) {
        CHECK(!stack && !up, "HCI init failure: no abort, start returns false");
        CHECK(in->attempted && in->failed && !in->stack_ok && in->err == ESP_FAIL && strstr(in->reason, "HCI"), "reason recorded: %s (err %d)", in->reason, in->err);
        CHECK(in->pre_free == 21000 && in->pre_largest == 7400 && in->fail_free == 21000, "heap figures recorded before / after (%u %u %u)", in->pre_free, in->pre_largest, in->fail_free);
        CHECK(!ble_central_stack_init(), "no blind retry in the same boot");
        CHECK(!xTaskGetHandle("nimble_host") && !xTaskGetHandle("ble_mgr"), "no Bluetooth task was created");
    } else {
        CHECK(stack && !up, "host task cannot be created: start returns false");
        CHECK(in->failed && strstr(in->reason, "host task"), "reason recorded: %s", in->reason);
        CHECK(!xTaskGetHandle("ble_mgr"), "manager task not created either");
    }
    CHECK(ble_central_unavailable(), "unavailable flag");
    /* everything the UI / app does afterwards must be harmless */
    ble_central_enable_sensors(true);
    ble_central_set_paired(PLAT_SENS_POWER, MAC, 0, "XDS-A001");
    ble_central_set_disabled(PLAT_SENS_HR, true);
    ble_central_scan_for(PLAT_SENS_POWER); ble_central_scan_for(-1);
    ble_central_set_standby(true); ble_central_set_wheel_mm(2096);
    plat_sensors_t s; ble_central_snapshot(&s);
    CHECK(!s.power_ok && !s.hr_ok && !ble_central_ready() && !ble_central_scanning(), "snapshot: no data, not ready");
    plat_found_t f[4]; CHECK(ble_central_found(PLAT_SENS_POWER, f, 4) == 0, "no pairing list");
    plat_phone_set_enabled(true); plat_phone_disconnect(); plat_phone_forget();
    plat_phone_status_t ps; plat_phone_status(&ps);
    CHECK(ps.state == PLAT_PHONE_UNAVAILABLE, "phone status says Bluetooth unavailable (state %d), never 'searching'", (int)ps.state);
    bc_live_t L; memset(&L, 0, sizeof L); plat_phone_publish_live(&L);
    uint8_t b[32] = { 0 }; plat_phone_notify_svc(0, b, 8);
    uint8_t chr; CHECK(plat_phone_take_svc(&chr, b, sizeof b) == 0, "nothing received");
    char r[64]; CHECK(plat_bt_unavailable(r, sizeof r) && r[0], "plat_bt_unavailable reason: %s", r);
    printf("initfail mode %d: %d checks, %d failed\n", mode, checks, fails);
    return fails ? 1 : 0;
}
