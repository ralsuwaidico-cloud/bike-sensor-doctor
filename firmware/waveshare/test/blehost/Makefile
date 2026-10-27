# BLE glue stress harness: the real main/ble_central.c + main/ble_link.c on a fake NimBLE (see stress.c).
#   make            ASan + UBSan, 1000 phone cycles          make tsan    ThreadSanitizer build + run
#   make FW=/path/to/other/firmware/waveshare OLD=1   (the exact 0.7.2 tree: ble_central_start() had no argument)
FW ?= ../..
CORE = $(FW)/components/bc_core
SRC = stress.c fake/fake_nimble.c $(FW)/main/ble_central.c $(FW)/main/ble_link.c \
      $(CORE)/bc_xds.c $(CORE)/bc_hr.c $(CORE)/bc_csc.c $(CORE)/bc_cp.c $(CORE)/bc_gatt.c $(CORE)/bc_pipe.c $(CORE)/bc_link.c $(CORE)/bc_ride.c
INC = -Ifake -I$(FW)/main -I$(FW)/main/app -I$(CORE)/include
CFLAGS = -D_GNU_SOURCE -std=gnu11 -g -O1 -Wall -Wno-unused-function -Wno-unused-parameter -Wno-missing-field-initializers -pthread
CYCLES ?= 1000
ifneq ($(OLD),)
CFLAGS += -DBLEHOST_072
endif
all: run prio-run initfail-run
# 0.7.3 Link 1.2.3 ride priority: LIVE cadence with and without a report transfer on a congested radio (prio.c)
PSRC = prio.c fake/fake_nimble.c $(FW)/main/ble_central.c $(FW)/main/ble_link.c \
      $(CORE)/bc_xds.c $(CORE)/bc_hr.c $(CORE)/bc_csc.c $(CORE)/bc_cp.c $(CORE)/bc_gatt.c $(CORE)/bc_pipe.c $(CORE)/bc_link.c $(CORE)/bc_ride.c \
      $(CORE)/bc_diag.c $(CORE)/bc_boot.c
prio: $(PSRC) fake/fake_nimble.h
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer $(INC) -o $@ $(PSRC) -lm
prio-run: prio
	ASAN_OPTIONS=detect_leaks=0 ./prio 40 30
	ASAN_OPTIONS=detect_leaks=0 ./prio 40 150
# 0.7.4: Bluetooth start-up failure (HCI init / host task) never aborts (initfail.c)
ISRC = initfail.c fake/fake_nimble.c $(FW)/main/ble_central.c $(FW)/main/ble_link.c \
      $(CORE)/bc_xds.c $(CORE)/bc_hr.c $(CORE)/bc_csc.c $(CORE)/bc_cp.c $(CORE)/bc_gatt.c $(CORE)/bc_pipe.c $(CORE)/bc_link.c $(CORE)/bc_ride.c
initfail: $(ISRC) fake/fake_nimble.h
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer $(INC) -o $@ $(ISRC) -lm
initfail-run: initfail
	ASAN_OPTIONS=detect_leaks=0 ./initfail 0
	ASAN_OPTIONS=detect_leaks=0 ./initfail 1
	ASAN_OPTIONS=detect_leaks=0 ./initfail 2
stress: $(SRC) fake/fake_nimble.h
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer $(INC) -o $@ $(SRC) -lm
stress_tsan: $(SRC) fake/fake_nimble.h
	$(CC) $(CFLAGS) -fsanitize=thread $(INC) -o $@ $(SRC) -lm
run: stress
	ASAN_OPTIONS=detect_leaks=1 ./stress $(CYCLES)
tsan: stress_tsan
	TSAN_OPTIONS="halt_on_error=0 report_signal_unsafe=0" ./stress_tsan $(CYCLES) 2> tsan.log; \
	  echo "ThreadSanitizer data-race reports: $$(grep -c 'WARNING: ThreadSanitizer: data race' tsan.log)"; \
	  grep -A6 'WARNING: ThreadSanitizer: data race' tsan.log | grep -E '#0 ' | sed 's/ (.*//' | sort | uniq -c | sort -rn | head -20
clean:
	rm -f stress stress_tsan tsan.log prio initfail
