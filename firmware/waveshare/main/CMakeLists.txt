idf_component_register(SRCS "main.c" "hw.c" "ble_xds.c" "net_wifi.c" "ui_diag.c"
                       INCLUDE_DIRS "."
                       REQUIRES bc_core lvgl esp_lvgl_port esp_lcd esp_lcd_gc9a01 esp_lcd_touch esp_lcd_touch_cst816s
                                bt nvs_flash fatfs wear_levelling esp_adc esp_driver_spi esp_driver_ledc esp_driver_i2c
                                esp_wifi esp_netif esp_event esp_timer esp_psram spi_flash app_update)
