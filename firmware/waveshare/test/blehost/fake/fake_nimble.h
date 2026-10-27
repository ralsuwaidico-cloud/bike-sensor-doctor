/*
 * Fake ESP-IDF + NimBLE API for the BLE glue stress harness (test/blehost). Only what main/ble_central.c and
 * main/ble_link.c use. Semantics follow NimBLE where it matters for crashes and races:
 *  - every API call takes the host lock (ble_hs_lock, recursive) like NimBLE; callbacks run on the HOST thread WITHOUT it;
 *  - GATT procedures complete asynchronously on the host thread; at most 4 procedures in flight (BLE_HS_ENOMEM beyond);
 *  - a broken connection first fails its procedures (callback status BLE_HS_ENOTCONN), THEN delivers BLE_GAP_EVENT_DISCONNECT;
 *  - connection handles are reused (smallest free), like the controller does;
 *  - ble_gatts_notify_custom always consumes the mbuf.
 * portENTER_CRITICAL is a real lock + a per-thread depth counter: taking the host lock inside it is reported (on the chip
 * that would block with interrupts masked).
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

/* ---- esp basics */
typedef int esp_err_t;
#define ESP_OK 0
#define ESP_FAIL -1
#define ESP_ERR_NVS_NOT_FOUND 0x1102
#define ESP_ERROR_CHECK(x) do { esp_err_t _e = (x); if (_e != ESP_OK) { fprintf(stderr, "ESP_ERROR_CHECK failed %d at %s:%d\n", _e, __FILE__, __LINE__); abort(); } } while (0)
#define RTC_NOINIT_ATTR
#define IRAM_ATTR
void fake_log(char lvl, const char *tag, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
#define ESP_LOGE(tag, ...) fake_log('E', tag, __VA_ARGS__)
#define ESP_LOGW(tag, ...) fake_log('W', tag, __VA_ARGS__)
#define ESP_LOGI(tag, ...) fake_log('I', tag, __VA_ARGS__)
#define ESP_LOGD(tag, ...) do { } while (0)
uint32_t esp_random(void);
void esp_fill_random(void *buf, size_t len);
typedef struct { char version[32]; char project_name[32]; char time[16]; char date[16]; uint8_t app_elf_sha256[32]; } esp_app_desc_t;
const esp_app_desc_t *esp_app_get_description(void);
uint32_t hw_millis(void);

/* ---- esp_timer */
typedef struct fake_timer *esp_timer_handle_t;
typedef void (*esp_timer_cb_t)(void *arg);
typedef struct { esp_timer_cb_t callback; void *arg; int dispatch_method; const char *name; bool skip_unhandled_events; } esp_timer_create_args_t;
esp_err_t esp_timer_create(const esp_timer_create_args_t *a, esp_timer_handle_t *out);
esp_err_t esp_timer_start_once(esp_timer_handle_t t, uint64_t us);
esp_err_t esp_timer_stop(esp_timer_handle_t t);
int64_t esp_timer_get_time(void);

/* ---- FreeRTOS */
typedef int BaseType_t; typedef unsigned UBaseType_t; typedef uint32_t TickType_t; typedef void *TaskHandle_t;
#define pdMS_TO_TICKS(ms) ((TickType_t)(ms))
#define pdTRUE 1
#define pdFALSE 0
#define pdPASS 1
typedef struct { pthread_mutex_t m; int init; } portMUX_TYPE;
#define portMUX_INITIALIZER_UNLOCKED { PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP, 1 }
void fake_crit_enter(portMUX_TYPE *m);
void fake_crit_exit(portMUX_TYPE *m);
#define portENTER_CRITICAL(m) fake_crit_enter(m)
#define portEXIT_CRITICAL(m) fake_crit_exit(m)
void vTaskDelay(TickType_t t);
BaseType_t xTaskCreatePinnedToCore(void (*fn)(void *), const char *name, uint32_t stack, void *arg, UBaseType_t prio, TaskHandle_t *h, BaseType_t core);
TaskHandle_t xTaskGetHandle(const char *name);
UBaseType_t uxTaskGetStackHighWaterMark(TaskHandle_t t);

/* ---- NVS */
typedef uint32_t nvs_handle_t;
typedef enum { NVS_READONLY, NVS_READWRITE } nvs_open_mode_t;
esp_err_t nvs_open(const char *ns, nvs_open_mode_t m, nvs_handle_t *h);
esp_err_t nvs_get_blob(nvs_handle_t h, const char *k, void *v, size_t *n);
esp_err_t nvs_set_blob(nvs_handle_t h, const char *k, const void *v, size_t n);
esp_err_t nvs_get_u8(nvs_handle_t h, const char *k, uint8_t *v);
esp_err_t nvs_set_u8(nvs_handle_t h, const char *k, uint8_t v);
esp_err_t nvs_get_u32(nvs_handle_t h, const char *k, uint32_t *v);
esp_err_t nvs_set_u32(nvs_handle_t h, const char *k, uint32_t v);
esp_err_t nvs_commit(nvs_handle_t h);
void nvs_close(nvs_handle_t h);

/* ---- NimBLE: errors, addresses, UUIDs */
#define BLE_HS_EAGAIN 1
#define BLE_HS_EALREADY 2
#define BLE_HS_EINVAL 3
#define BLE_HS_ENOENT 5
#define BLE_HS_ENOMEM 6
#define BLE_HS_ENOTCONN 7
#define BLE_HS_EAPP 9
#define BLE_HS_EBADDATA 10
#define BLE_HS_ETIMEOUT 13
#define BLE_HS_EDONE 14
#define BLE_HS_EBUSY 15
#define BLE_HS_EUNKNOWN 17
#define BLE_HS_ENOTSYNCED 22
#define BLE_HS_ERR_ATT_BASE 0x100
#define BLE_HS_FOREVER INT32_MAX
#define BLE_HS_CONN_HANDLE_NONE 0xffff
#define BLE_ERR_REM_USER_CONN_TERM 0x13
#define BLE_OWN_ADDR_PUBLIC 0
#define BLE_OWN_ADDR_RANDOM 1
typedef struct { uint8_t type; uint8_t val[6]; } ble_addr_t;
enum { BLE_UUID_TYPE_16 = 16, BLE_UUID_TYPE_32 = 32, BLE_UUID_TYPE_128 = 128 };
typedef struct { uint8_t type; } ble_uuid_t;
typedef struct { ble_uuid_t u; uint16_t value; } ble_uuid16_t;
typedef struct { ble_uuid_t u; uint8_t value[16]; } ble_uuid128_t;
typedef union { ble_uuid_t u; ble_uuid16_t u16; ble_uuid128_t u128; } ble_uuid_any_t;
#define BLE_UUID16_INIT(v) { .u = { .type = BLE_UUID_TYPE_16 }, .value = (v) }
#define BLE_UUID16_DECLARE(v) ((const ble_uuid_t *)(&(ble_uuid16_t)BLE_UUID16_INIT(v)))
#define BLE_UUID128_INIT(...) { .u = { .type = BLE_UUID_TYPE_128 }, .value = { __VA_ARGS__ } }
uint16_t ble_uuid_u16(const ble_uuid_t *u);
int ble_uuid_cmp(const ble_uuid_t *a, const ble_uuid_t *b);
#define BLE_GATT_DSC_CLT_CFG_UUID16 0x2902

/* ---- mbufs */
struct os_mbuf { uint16_t len; uint8_t data[512]; };
#define OS_MBUF_PKTLEN(om) ((om)->len)
int os_mbuf_copydata(const struct os_mbuf *om, int off, int len, void *dst);
int os_mbuf_append(struct os_mbuf *om, const void *data, uint16_t len);
struct os_mbuf *ble_hs_mbuf_from_flat(const void *buf, uint16_t len);
void fake_mbuf_free(struct os_mbuf *om);

/* ---- GAP */
enum { BLE_GAP_EVENT_CONNECT = 0, BLE_GAP_EVENT_DISCONNECT, BLE_GAP_EVENT_DISC, BLE_GAP_EVENT_DISC_COMPLETE, BLE_GAP_EVENT_ADV_COMPLETE,
       BLE_GAP_EVENT_ENC_CHANGE, BLE_GAP_EVENT_PASSKEY_ACTION, BLE_GAP_EVENT_NOTIFY_RX, BLE_GAP_EVENT_NOTIFY_TX, BLE_GAP_EVENT_SUBSCRIBE,
       BLE_GAP_EVENT_MTU, BLE_GAP_EVENT_REPEAT_PAIRING, BLE_GAP_EVENT_CONN_UPDATE };
#define BLE_GAP_REPEAT_PAIRING_RETRY 1
#define BLE_GAP_CONN_MODE_UND 2
#define BLE_GAP_DISC_MODE_GEN 2
#define BLE_SM_IOACT_DISP 2
#define BLE_SM_IOACT_NUMCMP 4
#define BLE_SM_IO_CAP_DISP_ONLY 0
#define BLE_SM_PAIR_KEY_DIST_ENC 1
#define BLE_SM_PAIR_KEY_DIST_ID 2
struct ble_gap_sec_state { unsigned encrypted : 1; unsigned authenticated : 1; unsigned bonded : 1; unsigned key_size : 5; };
struct ble_gap_conn_desc { struct ble_gap_sec_state sec_state; ble_addr_t our_id_addr, peer_id_addr, our_ota_addr, peer_ota_addr; uint16_t conn_handle, conn_itvl, conn_latency, supervision_timeout; uint8_t role; };
struct ble_gap_passkey_params { uint8_t action; uint32_t numcmp; };
struct ble_gap_event {
    uint8_t type;
    union {
        struct { int status; uint16_t conn_handle; } connect;
        struct { int reason; struct ble_gap_conn_desc conn; } disconnect;
        struct { int event_type; uint8_t length_data; ble_addr_t addr; int8_t rssi; const uint8_t *data; } disc;
        struct { int reason; } adv_complete;
        struct { int status; uint16_t conn_handle; } enc_change;
        struct { uint16_t conn_handle; struct ble_gap_passkey_params params; } passkey;
        struct { struct os_mbuf *om; uint16_t conn_handle; uint16_t attr_handle; uint8_t indication : 1; } notify_rx;
        struct { uint16_t conn_handle; uint16_t attr_handle; uint8_t reason; uint8_t prev_notify : 1, cur_notify : 1, prev_indicate : 1, cur_indicate : 1; } subscribe;
        struct { uint16_t conn_handle; uint16_t channel_id; uint16_t value; } mtu;
        struct { uint16_t conn_handle; } repeat_pairing;
    };
};
typedef int ble_gap_event_fn(struct ble_gap_event *ev, void *arg);
struct ble_gap_disc_params { uint16_t itvl, window; uint8_t filter_policy; uint8_t limited : 1, passive : 1, filter_duplicates : 1; };
struct ble_gap_adv_params { uint8_t conn_mode, disc_mode; uint16_t itvl_min, itvl_max; uint8_t channel_map, filter_policy, high_duty_cycle; };
struct ble_gap_conn_params;
struct ble_hs_adv_fields {
    uint8_t flags;
    const ble_uuid16_t *uuids16; uint8_t num_uuids16; unsigned uuids16_is_complete : 1;
    const ble_uuid128_t *uuids128; uint8_t num_uuids128; unsigned uuids128_is_complete : 1;
    const uint8_t *name; uint8_t name_len; unsigned name_is_complete : 1;
};
#define BLE_HS_ADV_F_DISC_GEN 0x02
#define BLE_HS_ADV_F_BREDR_UNSUP 0x04
int ble_hs_adv_parse_fields(struct ble_hs_adv_fields *f, const uint8_t *data, uint8_t len);
int ble_gap_disc(uint8_t own, int32_t ms, const struct ble_gap_disc_params *p, ble_gap_event_fn *cb, void *arg);
int ble_gap_disc_cancel(void);
int ble_gap_connect(uint8_t own, const ble_addr_t *peer, int32_t ms, const struct ble_gap_conn_params *p, ble_gap_event_fn *cb, void *arg);
int ble_gap_conn_cancel(void);
int ble_gap_terminate(uint16_t conn, uint8_t reason);
int ble_gap_conn_rssi(uint16_t conn, int8_t *rssi);
int ble_gap_conn_find(uint16_t conn, struct ble_gap_conn_desc *d);
int ble_gap_adv_set_fields(const struct ble_hs_adv_fields *f);
int ble_gap_adv_rsp_set_fields(const struct ble_hs_adv_fields *f);
int ble_gap_adv_start(uint8_t own, const ble_addr_t *direct, int32_t ms, const struct ble_gap_adv_params *p, ble_gap_event_fn *cb, void *arg);
int ble_gap_adv_stop(void);
struct ble_sm_io { uint8_t action; union { uint32_t passkey; uint8_t oob[16]; uint8_t numcmp_accept; }; };
int ble_sm_inject_io(uint16_t conn, struct ble_sm_io *io);

/* ---- GATT client */
struct ble_gatt_error { uint16_t status; uint16_t att_handle; };
struct ble_gatt_svc { uint16_t start_handle, end_handle; ble_uuid_any_t uuid; };
struct ble_gatt_chr { uint16_t def_handle, val_handle; uint8_t properties; ble_uuid_any_t uuid; };
struct ble_gatt_dsc { uint16_t handle; ble_uuid_any_t uuid; };
struct ble_gatt_attr { uint16_t handle, offset; struct os_mbuf *om; };
typedef int ble_gatt_mtu_fn(uint16_t conn, const struct ble_gatt_error *e, uint16_t mtu, void *arg);
typedef int ble_gatt_disc_svc_fn(uint16_t conn, const struct ble_gatt_error *e, const struct ble_gatt_svc *s, void *arg);
typedef int ble_gatt_chr_fn(uint16_t conn, const struct ble_gatt_error *e, const struct ble_gatt_chr *c, void *arg);
typedef int ble_gatt_dsc_fn(uint16_t conn, const struct ble_gatt_error *e, uint16_t chr_val, const struct ble_gatt_dsc *d, void *arg);
typedef int ble_gatt_attr_fn(uint16_t conn, const struct ble_gatt_error *e, struct ble_gatt_attr *a, void *arg);
int ble_gattc_exchange_mtu(uint16_t conn, ble_gatt_mtu_fn *cb, void *arg);
int ble_gattc_disc_all_svcs(uint16_t conn, ble_gatt_disc_svc_fn *cb, void *arg);
int ble_gattc_disc_svc_by_uuid(uint16_t conn, const ble_uuid_t *u, ble_gatt_disc_svc_fn *cb, void *arg);
int ble_gattc_disc_all_chrs(uint16_t conn, uint16_t s, uint16_t e, ble_gatt_chr_fn *cb, void *arg);
int ble_gattc_disc_chrs_by_uuid(uint16_t conn, uint16_t s, uint16_t e, const ble_uuid_t *u, ble_gatt_chr_fn *cb, void *arg);
int ble_gattc_disc_all_dscs(uint16_t conn, uint16_t s, uint16_t e, ble_gatt_dsc_fn *cb, void *arg);
int ble_gattc_write_flat(uint16_t conn, uint16_t h, const void *v, uint16_t n, ble_gatt_attr_fn *cb, void *arg);
int ble_gattc_read(uint16_t conn, uint16_t h, ble_gatt_attr_fn *cb, void *arg);
void ble_att_set_preferred_mtu(uint16_t mtu);

/* ---- GATT server */
#define BLE_GATT_ACCESS_OP_READ_CHR 0
#define BLE_GATT_ACCESS_OP_WRITE_CHR 1
#define BLE_GATT_CHR_F_READ 0x0002
#define BLE_GATT_CHR_F_WRITE_NO_RSP 0x0004
#define BLE_GATT_CHR_F_WRITE 0x0008
#define BLE_GATT_CHR_F_NOTIFY 0x0010
#define BLE_GATT_CHR_F_READ_ENC 0x0200
#define BLE_GATT_CHR_F_READ_AUTHEN 0x0400
#define BLE_GATT_CHR_F_WRITE_ENC 0x1000
#define BLE_GATT_CHR_F_WRITE_AUTHEN 0x2000
#define BLE_GATT_SVC_TYPE_PRIMARY 1
#define BLE_ATT_ERR_INSUFFICIENT_AUTHEN 0x05
#define BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN 0x0d
#define BLE_ATT_ERR_UNLIKELY 0x0e
#define BLE_ATT_ERR_INSUFFICIENT_RES 0x11
#define BLE_ATT_ERR_WRITE_NOT_PERMITTED 0x03
struct ble_gatt_access_ctxt { uint8_t op; struct os_mbuf *om; };
typedef int ble_gatt_access_fn(uint16_t conn, uint16_t attr, struct ble_gatt_access_ctxt *c, void *arg);
struct ble_gatt_chr_def { const ble_uuid_t *uuid; ble_gatt_access_fn *access_cb; void *arg; void *descriptors; uint16_t flags; uint8_t min_key_size; uint16_t *val_handle; };
struct ble_gatt_svc_def { uint8_t type; const ble_uuid_t *uuid; const struct ble_gatt_svc_def **includes; const struct ble_gatt_chr_def *characteristics; };
int ble_gatts_count_cfg(const struct ble_gatt_svc_def *defs);
int ble_gatts_add_svcs(const struct ble_gatt_svc_def *defs);
int ble_gatts_notify_custom(uint16_t conn, uint16_t h, struct os_mbuf *om);
void ble_svc_gap_init(void);
void ble_svc_gatt_init(void);
const char *ble_svc_gap_device_name(void);
int ble_svc_gap_device_name_set(const char *n);

/* ---- host, store, ids */
struct ble_hs_cfg { void (*reset_cb)(int); void (*sync_cb)(void); uint8_t sm_io_cap; unsigned sm_oob_data_flag : 1, sm_bonding : 1, sm_mitm : 1, sm_sc : 1, sm_keypress : 1; uint8_t sm_our_key_dist, sm_their_key_dist; };
extern struct ble_hs_cfg ble_hs_cfg;
#define BLE_STORE_OBJ_TYPE_OUR_SEC 1
#define BLE_STORE_OBJ_TYPE_PEER_SEC 2
int ble_store_util_count(int type, int *out);
int ble_store_util_delete_peer(const ble_addr_t *a);
int ble_store_clear(void);
int ble_hs_util_ensure_addr(int prefer_random);
int ble_hs_id_infer_auto(int privacy, uint8_t *own);
int ble_hs_id_gen_rnd(int nrpa, ble_addr_t *out);
int ble_hs_id_set_rnd(const uint8_t *addr);
esp_err_t nimble_port_init(void);
void nimble_port_run(void);
void nimble_port_freertos_init(void (*fn)(void *));
void nimble_port_freertos_deinit(void);

/* ---- NimBLE porting layer events (the 0.7.3 central runs its manager on the host task through these) */
struct ble_npl_event;
typedef void ble_npl_event_fn(struct ble_npl_event *ev);
struct ble_npl_event { bool queued; ble_npl_event_fn *fn; void *arg; struct ble_npl_event *next; };
struct ble_npl_eventq { int dummy; };
struct ble_npl_eventq *nimble_port_get_dflt_eventq(void);
void ble_npl_event_init(struct ble_npl_event *ev, ble_npl_event_fn *fn, void *arg);
void ble_npl_eventq_put(struct ble_npl_eventq *q, struct ble_npl_event *ev);
void *ble_npl_event_get_arg(struct ble_npl_event *ev);

/* ---- harness control (fake_nimble.c) */
typedef struct {
    /* fault injection probabilities in 1/1000 per opportunity */
    int p_disconnect_per_proc, p_att_error, p_bad_packet, p_other_handle, p_cccd_read_mismatch, p_cccd_read_fail, p_no_mtu, p_conn_fail, p_enomem;
    int speed;                       /* virtual ms per real ms */
    bool meter_in_range, meter_streams;
    int phone_cycles_target;
    /* 0.7.3 Link 1.2.3 */
    int phone_mtu;                   /* ATT MTU the phone negotiates right after connecting (0 = none: stays 23) */
    bool strict_mtu;                 /* a notification longer than MTU-3 is a violation */
    bool radio; int radio_itvl_ms, radio_per_event;   /* msys pool (12) + the radio draining it per connection event */
    void (*on_phone_rx)(uint16_t handle, const uint8_t *b, uint16_t n, uint32_t t_ms);
} fake_cfg_t;
extern fake_cfg_t g_fake;
typedef struct {
    uint64_t connects, disconnects, procs, proc_enomem, notifies_rx, bad_packets, phone_connects, phone_disconnects, phone_notifies,
             cccd_writes, mtu_timeouts, npl_events, crit_lock_violations, foreign_gatt_ops, phone_killed_by_sensor, bad_writes, stale_conn_ops,
             oversize_notifies, notify_enomem;
    char first_violation[200];
} fake_stats_t;
extern fake_stats_t g_fstats;
void fake_start_world(void);
void fake_stop_world(void);
void fake_phone_cycle(bool enc_ok, int hold_ms, int writes);   /* one phone connect -> encrypt -> subscribe -> writes -> disconnect */
void fake_violation(const char *fmt, ...);
uint16_t ble_att_mtu(uint16_t conn);
int os_msys_num_free(void);
uint16_t fake_server_handle(int index);          /* the board's GATT server: 0 INFO, 1 LIVE, 2 INPUT, 3 CTRL, 4 SYNC, 5 EVENTS */
void fake_phone_write(uint16_t handle, const uint8_t *b, uint16_t n);
int fake_server_read(int index, uint8_t *out, int cap);   /* bytes, -1 on error */
uint32_t fake_now(void);
void fake_sleep_v(uint32_t vms);
