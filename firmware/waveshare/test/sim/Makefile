# PC preview + UI test harness. Needs ../../build/config/sdkconfig.h (run an ESP-IDF build once) so LVGL is configured
# exactly like the firmware.
FW=../..
LVGL=$(FW)/components/lvgl
CFG=$(FW)/build/config
INC=-I. -I$(CFG) -I$(LVGL) -I$(LVGL)/src -I$(FW)/main/app -I$(FW)/main/ui -I$(FW)/components/bc_core/include
DEFS=-DLV_CONF_KCONFIG_EXTERNAL_INCLUDE='"sdkconfig.h"' -DLV_CONF_SKIP
APP=$(FW)/main/app/app.c $(wildcard $(FW)/main/ui/*.c) $(wildcard $(FW)/main/fonts/*.c) \
    $(FW)/components/bc_core/bc_xds.c $(FW)/components/bc_core/bc_hr.c $(FW)/components/bc_core/bc_profile.c \
    $(FW)/components/bc_core/bc_ride.c $(FW)/components/bc_core/bc_coach.c $(FW)/components/bc_core/bc_demo.c
sim: sim_main.c plat_host.c $(APP) liblvgl.a
	$(CC) -O1 -g -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers $(DEFS) $(INC) -o $@ sim_main.c plat_host.c $(APP) liblvgl.a -lm
liblvgl.a:
	$(MAKE) -f Makefile.lvgl -j16
run: sim
	./sim out
clean:
	rm -rf sim out simfs obj liblvgl.a
