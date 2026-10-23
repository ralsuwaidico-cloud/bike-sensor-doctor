/* Phase A Wi-Fi check: bring the radio up, scan once, report what was found, turn the radio off again.
 * No network is joined and no credentials are stored in this build. */
#include <stdio.h>
#include <string.h>
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "hw.h"

static char s_best[3][33];
static int s_count = -1;

void net_wifi_scan_once(void)
{
    esp_netif_init();
    esp_event_loop_create_default();
    esp_netif_create_default_wifi_sta();
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    if (esp_wifi_init(&cfg) != ESP_OK || esp_wifi_set_mode(WIFI_MODE_STA) != ESP_OK || esp_wifi_start() != ESP_OK) {
        g_selftest.wifi = HW_FAIL; snprintf(g_selftest.wifi_s, sizeof g_selftest.wifi_s, "radio init failed"); return;
    }
    wifi_scan_config_t sc = { 0 };
    esp_err_t e = esp_wifi_scan_start(&sc, true);
    uint16_t n = 0; esp_wifi_scan_get_ap_num(&n);
    wifi_ap_record_t rec[10]; uint16_t got = 10; esp_wifi_scan_get_ap_records(&got, rec);
    for (int i = 0; i < 3 && i < got; i++) snprintf(s_best[i], sizeof s_best[i], "%s", (char *)rec[i].ssid);
    s_count = n;
    esp_wifi_stop();
    g_selftest.wifi = (e == ESP_OK) ? HW_PASS : HW_FAIL;
    snprintf(g_selftest.wifi_s, sizeof g_selftest.wifi_s, e == ESP_OK ? "%u networks seen" : "scan error", n);
    ESP_LOGI("selftest", "wifi     %s  %s  (strongest: %s, %s)", e == ESP_OK ? "PASS" : "FAIL", g_selftest.wifi_s, s_best[0], s_best[1]);
}
