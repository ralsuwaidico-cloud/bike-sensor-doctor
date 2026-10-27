CORE=../../components/bc_core
CFLAGS=-std=c99 -Wall -Wextra -Werror -O1 -I$(CORE)/include
all: test_bc_xds test_bc_core test_bc_pipe test_bc_diag test_bc_storage test_bc_bootrec test_storage_fixture test_partitions gen_diag_fixture test_bc_link13 gen_link13_fixture
	./test_bc_xds
	./test_bc_core
	./test_bc_pipe
	./test_bc_diag
	./test_bc_storage
	./test_bc_bootrec
	./test_storage_fixture
	./test_partitions
	./test_bc_link13
	./gen_link13_fixture --check fixtures/link13_fw_fixture.json fixtures/Link13FirmwareFixture.swift
	./gen_diag_fixture --check fixtures/diag_fw_fixture.json fixtures/DiagFirmwareFixture.swift
test_bc_xds: test_bc_xds.c $(CORE)/bc_xds.c
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -o $@ $^
test_bc_core: test_bc_core.c $(CORE)/bc_xds.c $(CORE)/bc_hr.c $(CORE)/bc_csc.c $(CORE)/bc_profile.c $(CORE)/bc_ride.c $(CORE)/bc_coach.c $(CORE)/bc_demo.c $(CORE)/bc_wifi.c $(CORE)/bc_link.c $(CORE)/bc_power.c
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -o $@ $^ -lm
# Link 1.2.3 cross-test fixture for the iOS tests (ios/BikeComputerTests/Fixtures/diag_fw_fixture.json + DiagFirmwareFixture.swift)
gen_diag_fixture: gen_diag_fixture.c diag_fixture.h $(CORE)/bc_diag.c $(CORE)/bc_boot.c $(CORE)/bc_link.c $(CORE)/bc_pipe.c $(CORE)/bc_ride.c
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -o $@ gen_diag_fixture.c $(CORE)/bc_diag.c $(CORE)/bc_boot.c $(CORE)/bc_link.c $(CORE)/bc_pipe.c $(CORE)/bc_ride.c -lm
fixture: gen_diag_fixture
	mkdir -p fixtures && ./gen_diag_fixture fixtures/diag_fw_fixture.json fixtures/DiagFirmwareFixture.swift
test_bc_diag: test_bc_diag.c diag_fixture.h $(CORE)/bc_diag.c $(CORE)/bc_boot.c $(CORE)/bc_link.c $(CORE)/bc_pipe.c $(CORE)/bc_ride.c
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -o $@ $(filter %.c,$^) -lm
# 0.7.4 storage failure categories (recovery screen, Device Health, BLE storage status)
test_bc_storage: test_bc_storage.c $(CORE)/bc_storage.c
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -o $@ $^
# 0.7.4 boot-record ring (NVS, FAT-independent crash / Bluetooth start-up evidence)
test_bc_bootrec: test_bc_bootrec.c $(CORE)/bc_bootrec.c $(CORE)/bc_diag.c $(CORE)/bc_boot.c $(CORE)/bc_link.c $(CORE)/bc_pipe.c $(CORE)/bc_ride.c
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -o $@ $(filter %.c,$^) -lm
# 0.7.4 the REAL corrupted filesystem head from the owner's pre-0.7.3 backup (FAT metadata only, no file contents)
test_storage_fixture: test_storage_fixture.c $(CORE)/bc_storage.c fixtures/storage_073_head.bin
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -o $@ test_storage_fixture.c $(CORE)/bc_storage.c
# partition-table compatibility (0.7.2 -> 0.7.3): old and new binary tables + the CSV + every kit app image
test_partitions: test_partitions.c
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -o $@ $^
test_bc_pipe: test_bc_pipe.c $(CORE)/bc_gatt.c $(CORE)/bc_pipe.c $(CORE)/bc_cp.c $(CORE)/bc_xds.c $(CORE)/bc_link.c $(CORE)/bc_ride.c
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -o $@ $^ -lm
# 0.7.5 Link 1.3 (BLE_CONTRACT.md v1.1): codec + coach mirroring
L13=$(CORE)/bc_link13.c $(CORE)/bc_cmirror.c $(CORE)/bc_link.c $(CORE)/bc_diag.c $(CORE)/bc_ride.c $(CORE)/bc_boot.c $(CORE)/bc_pipe.c
test_bc_link13: test_bc_link13.c $(L13)
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -o $@ $^ -lm
# Link 1.3 cross-test fixture for the iOS tests (ios/BikeComputerTests/Fixtures/link13_fw_fixture.json + Link13FirmwareFixture.swift)
gen_link13_fixture: gen_link13_fixture.c $(L13)
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -o $@ $^ -lm
fixture13: gen_link13_fixture
	mkdir -p fixtures && ./gen_link13_fixture fixtures/link13_fw_fixture.json fixtures/Link13FirmwareFixture.swift
clean:
	rm -f test_bc_xds test_bc_core test_bc_pipe test_bc_diag test_bc_storage test_bc_bootrec test_storage_fixture test_partitions gen_diag_fixture test_bc_link13 gen_link13_fixture

# LVGL's built-in printf has no float support: any %f / %.Nf passed to an lv_*_fmt call corrupts the arguments and crashes
# (root cause of the 0.1.0-diag reboot loop). This check fails the build if one is reintroduced.
lint:
	@python3 lint_lvgl_fmt.py ../../main ../../components/bc_core
