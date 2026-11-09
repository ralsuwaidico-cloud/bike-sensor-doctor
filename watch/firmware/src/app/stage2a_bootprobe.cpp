// Stage 2a boot probe — a tiny test program used ONLY in the emulator (QEMU) in CI to check the factory-preserving
// installation plan against the factory bootloader. Never flashed to the watch. It prints which partition it was booted
// from, where the default settings partition ("nvs") is, and writes one setting and one file so the test can prove that
// the factory regions are not touched.
#include <Arduino.h>
#include <LittleFS.h>
#include <Preferences.h>
#include <esp_ota_ops.h>
#include <esp_partition.h>

#ifndef BOOTPROBE_ROLE_ID
#define BOOTPROBE_ROLE_ID 0
#endif
static const char* role() {
    switch (BOOTPROBE_ROLE_ID) {
        case 1: return "FACTORY_STANDIN";
        case 2: return "CYCLIFT";
        case 3: return "CYCLIFT_CRASH";
        default: return "UNKNOWN";
    }
}

void setup() {
    Serial.begin(115200);
    delay(20);
    const esp_partition_t* run = esp_ota_get_running_partition();
    Serial.printf("\nBOOTPROBE role=%s running=%s addr=0x%06lx\n", role(), run ? run->label : "?",
                  (unsigned long)(run ? run->address : 0));
#if BOOTPROBE_ROLE_ID == 3
    Serial.println("BOOTPROBE crash_on_purpose");
    Serial.flush();
    abort();
#endif
    const esp_partition_t* nvs = esp_partition_find_first(ESP_PARTITION_TYPE_DATA, ESP_PARTITION_SUBTYPE_DATA_NVS, "nvs");
    Serial.printf("BOOTPROBE default_nvs=0x%06lx\n", (unsigned long)(nvs ? nvs->address : 0));
    Preferences p;
    if (p.begin("probe", false)) {
        uint32_t c = p.getUInt("boots", 0) + 1;
        p.putUInt("boots", c);
        p.end();
        Serial.printf("BOOTPROBE nvs_write_ok boots=%lu\n", (unsigned long)c);
    } else {
        Serial.println("BOOTPROBE nvs_write_fail");
    }
    if (esp_partition_find_first(ESP_PARTITION_TYPE_DATA, ESP_PARTITION_SUBTYPE_ANY, "littlefs")) {
        if (LittleFS.begin(true, "/littlefs", 4, "littlefs")) {
            File f = LittleFS.open("/probe.txt", "w");
            if (f) { f.print("probe"); f.close(); }
            Serial.println("BOOTPROBE littlefs_write_ok");
            LittleFS.end();
        } else {
            Serial.println("BOOTPROBE littlefs_fail");
        }
    }
    esp_partition_iterator_t it = esp_partition_find(ESP_PARTITION_TYPE_ANY, ESP_PARTITION_SUBTYPE_ANY, NULL);
    while (it) {
        const esp_partition_t* q = esp_partition_get(it);
        Serial.printf("BOOTPROBE part %s 0x%06lx 0x%06lx\n", q->label, (unsigned long)q->address, (unsigned long)q->size);
        it = esp_partition_next(it);
    }
    esp_partition_iterator_release(it);
    Serial.println("BOOTPROBE done");
    Serial.flush();
}

void loop() { delay(1000); }
