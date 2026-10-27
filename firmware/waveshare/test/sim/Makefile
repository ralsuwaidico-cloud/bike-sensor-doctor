# PC preview + UI test harness. Needs ../../build/config/sdkconfig.h (run an ESP-IDF build once) so LVGL is configured
# exactly like the firmware.
FW=../..
LVGL=$(FW)/components/lvgl
CFG=$(FW)/build/config
INC=-I. -I$(CFG) -I$(LVGL) -I$(LVGL)/src -I$(FW)/main/app -I$(FW)/main/ui -I$(FW)/components/bc_core/include
DEFS=-DLV_CONF_KCONFIG_EXTERNAL_INCLUDE='"sdkconfig.h"' -DLV_CONF_SKIP
APP=$(FW)/main/app/app.c $(FW)/main/app/app_power.c $(FW)/main/app/app_psvc.c $(FW)/main/app/app_diag.c $(wildcard $(FW)/main/ui/*.c) $(wildcard $(FW)/main/fonts/*.c) \
    $(FW)/components/bc_core/bc_xds.c $(FW)/components/bc_core/bc_cp.c $(FW)/components/bc_core/bc_gatt.c $(FW)/components/bc_core/bc_pipe.c $(FW)/components/bc_core/bc_hr.c $(FW)/components/bc_core/bc_csc.c $(FW)/components/bc_core/bc_profile.c \
    $(FW)/components/bc_core/bc_ride.c $(FW)/components/bc_core/bc_coach.c $(FW)/components/bc_core/bc_demo.c $(FW)/components/bc_core/bc_wifi.c $(FW)/components/bc_core/bc_link.c $(FW)/components/bc_core/bc_power.c \
    $(FW)/components/bc_core/bc_diag.c $(FW)/components/bc_core/bc_boot.c $(FW)/components/bc_core/bc_storage.c $(FW)/components/bc_core/bc_bootrec.c
sim: sim_main.c plat_host.c sim_gatt.c sim.h $(APP) liblvgl.a
	$(CC) -O1 -g -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers $(DEFS) $(INC) -o $@ sim_main.c plat_host.c sim_gatt.c $(APP) liblvgl.a -lm
liblvgl.a:
	$(MAKE) -f Makefile.lvgl -j16
run: sim
	./sim out
# 0.7.3: the same harness with AddressSanitizer + UndefinedBehaviorSanitizer (firmware code; LVGL itself is the plain library)
sim_asan: sim_main.c plat_host.c sim_gatt.c sim.h $(APP) liblvgl.a
	$(CC) -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers $(DEFS) $(INC) -o $@ sim_main.c plat_host.c sim_gatt.c $(APP) liblvgl.a -lm
run-asan: sim_asan
	ASAN_OPTIONS=detect_leaks=0 ./sim_asan out_asan
clean:
	rm -rf sim sim_asan out out_asan simfs obj liblvgl.a
