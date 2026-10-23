idf_component_register(SRCS "esp_lcd_gc9a01.c"
                       INCLUDE_DIRS "include"
                       REQUIRES "esp_lcd"
                       PRIV_REQUIRES "driver")


# replaces cu_pkg_define_version() from the registry-only cmake_utilities component
target_compile_definitions(${COMPONENT_LIB} PRIVATE ESP_LCD_GC9A01_VER_MAJOR=2 ESP_LCD_GC9A01_VER_MINOR=0 ESP_LCD_GC9A01_VER_PATCH=4)
