set(REQ "driver" "esp_lcd")

# esp_lcd_touch is declared in idf_component.yml, which is only acted upon by the
# component manager. Add it explicitly when the component manager is disabled.
idf_build_get_property(idf_component_manager IDF_COMPONENT_MANAGER)
if(NOT idf_component_manager)
    list(APPEND REQ esp_lcd_touch)
endif()

idf_component_register(SRCS "esp_lcd_touch_cst816s.c" INCLUDE_DIRS "include" REQUIRES ${REQ})

target_compile_definitions(${COMPONENT_LIB} PRIVATE ESP_LCD_TOUCH_CST816S_VER_MAJOR=1 ESP_LCD_TOUCH_CST816S_VER_MINOR=1 ESP_LCD_TOUCH_CST816S_VER_PATCH=2)
