/* bc_bootrec (0.7.4): boot-record ring kept in NVS, independent of the FAT. Host test. */
#include "bc_bootrec.h"
#include "bc_diag.h"
#include <stdio.h>
#include <string.h>

static int checks, fails;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(void)
{
    bc_bootring_t g; bc_bootring_init(&g); bc_bootring_seal(&g);
    CHECK(bc_bootring_valid(&g, sizeof g) && g.count == 0 && !bc_bootring_get(&g, 0), "empty ring valid");
    CHECK(sizeof g <= 800, "ring blob %zu bytes (bounded: 4 records + the pinned last Bluetooth attempt)", sizeof g);
    /* SYNTHETIC records (QA QF-14: these figures are made up for the test, not measured on any board): three boots, each
       failing at the HCI/host step */
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
    /* rc2 (QF-06): the pinned last Bluetooth attempt survives any number of skipped boots */
    bc_bootring_init(&g);
    bc_bootrec_t *a = bc_bootring_push(&g, 500); a->bt_result = BC_BT_FAIL_HOST_INIT; a->bt[0].free_int = 12345; bc_bootring_note_bt(&g);
    CHECK(g.last_bt_try.boot == 500 && g.last_bt_try.bt[0].free_int == 12345, "failed attempt pinned");
    for (uint32_t b = 501; b < 520; b++) { bc_bootrec_t *x = bc_bootring_push(&g, b); x->bt_result = BC_BT_SKIPPED; bc_bootring_note_bt(&g); }
    bc_bootring_push(&g, 520); bc_bootring_note_bt(&g);   /* NOT_TRIED */
    bc_bootring_seal(&g);
    CHECK(bc_bootring_valid(&g, sizeof g) && g.last_bt_try.boot == 500 && g.last_bt_try.bt[0].free_int == 12345 && bc_bootring_get(&g, 3)->boot == 517,
          "20 skipped / not-tried boots later the attempt of boot 500 is still there");
    a = bc_bootring_push(&g, 521); a->bt_result = BC_BT_OK; bc_bootring_note_bt(&g);
    CHECK(g.last_bt_try.boot == 521 && g.last_bt_try.bt_result == BC_BT_OK, "a newer real attempt replaces it");
    /* rc2 (QF-09): crash streak from the NVS ring, independent of RTC memory and of the 20 s stable mark */
    bc_bootring_init(&g);
    CHECK(bc_bootring_crash_streak(&g) == 0, "empty ring: streak 0");
    bc_bootring_push(&g, 1)->reset = BC_RST_POWERON;
    for (uint32_t b = 2; b < 5; b++) bc_bootring_push(&g, b)->reset = b == 3 ? BC_RST_WDT : BC_RST_PANIC;
    CHECK(bc_bootring_crash_streak(&g) == 3, "power-on then 3 crash resets -> 3 (got %d)", bc_bootring_crash_streak(&g));
    bc_bootring_push(&g, 5)->reset = BC_RST_BROWNOUT;
    CHECK(bc_bootring_crash_streak(&g) == 4, "ring full of crash resets -> 4");
    bc_bootring_push(&g, 6)->reset = BC_RST_SW;
    CHECK(bc_bootring_crash_streak(&g) == 0, "a software restart (RETRY / install) ends it");
    char small[10]; CHECK(bc_bootrec_describe(bc_bootring_get(&g, 0), small, sizeof small) <= 9, "describe truncates");
    printf("test_bc_bootrec: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
