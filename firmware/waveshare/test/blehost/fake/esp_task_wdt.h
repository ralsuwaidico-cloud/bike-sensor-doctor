#pragma once
#include "fake_nimble.h"
/* task watchdog (0.7.4-rc2 guard around the Bluetooth stack start): recorded only */
typedef struct { uint32_t timeout_ms; uint32_t idle_core_mask; bool trigger_panic; } esp_task_wdt_config_t;
esp_err_t esp_task_wdt_reconfigure(const esp_task_wdt_config_t *c);
esp_err_t esp_task_wdt_add(TaskHandle_t t);
esp_err_t esp_task_wdt_delete(TaskHandle_t t);
extern int g_fake_wdt_subscribed; extern uint32_t g_fake_wdt_timeout_ms; extern bool g_fake_wdt_panic; extern int g_fake_wdt_guard_seen;
#define CONFIG_ESP_TASK_WDT_EN 1
#define CONFIG_ESP_TASK_WDT_TIMEOUT_S 5
#define CONFIG_ESP_TASK_WDT_CHECK_IDLE_TASK_CPU0 1
#define CONFIG_ESP_TASK_WDT_CHECK_IDLE_TASK_CPU1 1
