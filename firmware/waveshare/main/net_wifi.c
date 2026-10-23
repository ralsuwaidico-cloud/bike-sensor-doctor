/* Optional Wi-Fi: nothing in this firmware needs a network. When the rider switches Wi-Fi on, the radio scans once
 * (proves it works, count shown in Diagnostics) and is switched off again. No network is joined, no credentials stored.
 * Joining a network for sync / updates comes with the companion apps. */
#include <stdio.h>
#include <string.h>
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "hw.h"

static int s_count = -1;
static bool s_inited;

int net_wifi_count(void) { return s_count; }

void net_wifi_off(void) { if (s_inited) esp_wifi_stop(); }

void net_wifi_scan_once(void)
{
    if (!s_inited) {
        esp_netif_init();
        esp_event_loop_create_default();
        esp_netif_create_default_wifi_sta();
        wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
        if (esp_wifi_init(&cfg) != ESP_OK || esp_wifi_set_mode(WIFI_MODE_STA) != ESP_OK) {
            g_selftest.wifi = HW_FAIL; snprintf(g_selftest.wifi_s, sizeof g_selftest.wifi_s, "radio init failed"); return;
        }
        s_inited = true;
    }
    if (esp_wifi_start() != ESP_OK) { g_selftest.wifi = HW_FAIL; snprintf(g_selftest.wifi_s, sizeof g_selftest.wifi_s, "start failed"); return; }
    wifi_scan_config_t sc = { 0 };
    esp_err_t e = esp_wifi_scan_start(&sc, true);
    uint16_t n = 0; esp_wifi_scan_get_ap_num(&n);
    esp_wifi_clear_ap_list();
    s_count = n;
    esp_wifi_stop();
    g_selftest.wifi = (e == ESP_OK) ? HW_PASS : HW_FAIL;
    snprintf(g_selftest.wifi_s, sizeof g_selftest.wifi_s, e == ESP_OK ? "%u networks seen" : "scan error", n);
    ESP_LOGI("wifi", "scan: %s", g_selftest.wifi_s);
}
