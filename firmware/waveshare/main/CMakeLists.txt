file(GLOB UI_SRCS "ui/*.c")
file(GLOB FONT_SRCS "fonts/*.c")
idf_component_register(SRCS "main.c" "hw.c" "ble_central.c" "ble_link.c" "net_wifi.c" "plat_esp.c" "diag_esp.c" "app/app.c" "app/app_power.c" "app/app_psvc.c" "app/app_diag.c" "app/app_link13.c" ${UI_SRCS} ${FONT_SRCS}
                       INCLUDE_DIRS "." "app" "ui"
                       REQUIRES bc_core lvgl esp_lvgl_port esp_lcd esp_lcd_gc9a01 esp_lcd_touch esp_lcd_touch_cst816s
                                bt nvs_flash fatfs wear_levelling esp_adc esp_driver_spi esp_driver_ledc esp_driver_i2c
                                esp_wifi esp_netif esp_event esp_timer esp_psram spi_flash app_update esp_driver_gpio esp_hw_support espcoredump esp_partition)
