# bc_core — portable cycling-computer core (C99, no ESP-IDF dependencies). Mirrors app/.../core on Android.
idf_component_register(SRCS "bc_xds.c" "bc_cp.c" "bc_gatt.c" "bc_pipe.c" "bc_hr.c" "bc_csc.c" "bc_profile.c" "bc_ride.c" "bc_coach.c" "bc_demo.c" "bc_wifi.c" "bc_link.c" "bc_power.c" "bc_diag.c" "bc_boot.c" "bc_storage.c" "bc_bootrec.c" INCLUDE_DIRS "include")
