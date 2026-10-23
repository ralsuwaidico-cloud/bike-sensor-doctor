# bc_core — portable cycling-computer core (C99, no ESP-IDF dependencies). Mirrors app/.../core on Android.
idf_component_register(SRCS "bc_xds.c" "bc_hr.c" "bc_profile.c" "bc_ride.c" "bc_coach.c" "bc_demo.c" "bc_wifi.c" INCLUDE_DIRS "include")
