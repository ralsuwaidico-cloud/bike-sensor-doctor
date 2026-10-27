/* bc_bootrec (0.7.4): boot-record ring kept in NVS, independent of the FAT. Host test. */
#include "bc_bootrec.h"
#include <stdio.h>
#include <string.h>

static int checks, fails;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(void)
{
    bc_bootring_t g; bc_bootring_init(&g); bc_bootring_seal(&g);
    CHECK(bc_bootring_valid(&g, sizeof g) && g.count == 0 && !bc_bootring_get(&g, 0), "empty ring valid");
    CHECK(sizeof g <= 600, "ring blob %zu bytes (bounded)", sizeof g);
    /* the 27 Oct board: three boots, each failing at the HCI/host step, as measured in the instrumented sequence */
    for (uint32_t b = 339; b < 342; b++) {
        bc_bootrec_t *r = bc_bootring_push(&g, b);
        r->reset = b == 339 ? 1 : 3; r->bt_result = BC_BT_FAIL_HOST_INIT; r->bt[0].free_int = 30000; r->bt[0].largest_int = 7000;
        r->bt[3].rc = -1; r->fail_alloc_size = 8256; r->fail_alloc_caps = 0x804; r->fail_allocs = 1; r->storage = 3;
    }
    bc_bootring_seal(&g);
    CHECK(bc_bootring_valid(&g, sizeof g) && g.count == 3 && bc_bootring_get(&g, 0)->boot == 341 && bc_bootring_get(&g, 2)->boot == 339, "newest first");
    bc_bootrec_t *now = bc_bootring_push(&g, 342);
    CHECK(bc_bootring_bt_fail_streak(&g) == 3 && now->bt_result == BC_BT_NOT_TRIED, "three previous boots failed to start Bluetooth -> streak 3");
    now->bt_result = BC_BT_SKIPPED; bc_bootring_push(&g, 343);
    CHECK(bc_bootring_bt_fail_streak(&g) == 0, "a skipped boot ends the streak (RETRY counts again)");
    CHECK(g.count == BC_BOOTREC_N && bc_bootring_get(&g, 3)->boot == 340 && !bc_bootring_get(&g, 4), "ring keeps the newest %d", BC_BOOTREC_N);
    char line[400]; bc_bootrec_describe(bc_bootring_get(&g, 2), line, sizeof line);
    CHECK(strstr(line, "boot #341") && strstr(line, "HCI init failed") && strstr(line, "[3 rc -1") && strstr(line, "failed alloc 8256 B"), "describe: %s", line);
    bc_bootring_seal(&g); g.r[1].boot ^= 1; CHECK(!bc_bootring_valid(&g, sizeof g), "a changed byte -> invalid (CRC)");
    bc_bootring_seal(&g); CHECK(!bc_bootring_valid(&g, sizeof g - 4), "wrong blob length -> invalid");
    g.head = 9; bc_bootring_seal(&g); CHECK(!bc_bootring_valid(&g, sizeof g), "head out of range -> invalid");
    memset(&g, 0xFF, sizeof g); CHECK(!bc_bootring_valid(&g, sizeof g), "erased blob invalid");
    char small[10]; CHECK(bc_bootrec_describe(bc_bootring_get(&g, 0), small, sizeof small) <= 9, "describe truncates");
    printf("test_bc_bootrec: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
