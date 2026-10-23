CORE=../../components/bc_core
CFLAGS=-std=c99 -Wall -Wextra -Werror -O1 -I$(CORE)/include
all: test_bc_xds test_bc_core
	./test_bc_xds
	./test_bc_core
test_bc_xds: test_bc_xds.c $(CORE)/bc_xds.c
	$(CC) $(CFLAGS) -o $@ $^
test_bc_core: test_bc_core.c $(CORE)/bc_xds.c $(CORE)/bc_hr.c $(CORE)/bc_profile.c $(CORE)/bc_ride.c $(CORE)/bc_coach.c $(CORE)/bc_demo.c $(CORE)/bc_wifi.c
	$(CC) $(CFLAGS) -fsanitize=address,undefined -o $@ $^ -lm
clean:
	rm -f test_bc_xds test_bc_core

# LVGL's built-in printf has no float support: any %f / %.Nf passed to an lv_*_fmt call corrupts the arguments and crashes
# (root cause of the 0.1.0-diag reboot loop). This check fails the build if one is reintroduced.
lint:
	@python3 lint_lvgl_fmt.py ../../main ../../components/bc_core
