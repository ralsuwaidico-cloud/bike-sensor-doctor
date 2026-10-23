CFLAGS=-std=c99 -Wall -Wextra -Werror -O1 -I../../components/bc_core/include
all: test_bc_xds
	./test_bc_xds
test_bc_xds: test_bc_xds.c ../../components/bc_core/bc_xds.c
	$(CC) $(CFLAGS) -o $@ $^
clean:
	rm -f test_bc_xds

# LVGL's built-in printf has no float support: any %f / %.Nf passed to an lv_*_fmt call corrupts the arguments and crashes
# (root cause of the 0.1.0-diag reboot loop). This check fails the build if one is reintroduced.
lint:
	@python3 lint_lvgl_fmt.py ../../main ../../components/bc_core
