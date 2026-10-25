# Consolidated release — firmware 0.7.0 + iOS 0.8.0 (Rashed, 25 Oct 22:41)

One firmware release and one TestFlight build, same Link protocol v1.2 (docs/LINK_V1_2_SPEC.md) and profile schema.
Board state when requested: 0.6.0 rev 3 installed (touch dead after wake — fixed in 0.6.1, not yet installed); data was reset by Rashed → iPhone shows "Peer removed pairing information".

## Scope (audit first — do not rebuild what works)
Firmware 0.7.0 = 0.6.1 (touch/wake fix, SAFE MODE, Settings layout) + PAIRING_SYNC_BRIEF items:
- bonding lifecycle: fresh random static identity address after a bond wipe/data reset (so iOS re-discovers), handle BLE_GAP_EVENT_REPEAT_PAIRING by deleting the stale bond and accepting re-pair, correct advertising after reset, services intact after reconnect, diagnostics (disconnect reason, bonding state, auth result, psvc state) over serial + Device Health;
- compact PHONE screen (title, status Connected/Searching/Pairing/Disconnected, one primary action Connect/Repair/Disconnect, phone name, sync status, link ON/OFF, last sync; Help/Details page for text); no scrolling for essentials; audit other screens.
- profile sync hardening: validation of every field, ack semantics, persist last synced version/time, standalone→paired reconciliation, never touch rides/sensor pairings.
iOS 0.8.0 = 0.7.0 (build 36) + HYBRID_ROUTINES_BRIEF (templates on calendar, equipment, insight card, Train now, strength workout screen, direct templates) + PAIRING_SYNC_BRIEF items:
- staged connection UI with failure reasons; Connect/Repair/Disconnect/Forget/Retry sync/Diagnostics; detect ATT insufficient encryption/authentication + "peer removed pairing information" → Repair flow (explain, deep-link to Settings › Bluetooth for Forget, rescan by service/name, accept a new peripheral identifier for the same device_id); no contradictory states; background reconnect respects firmware states.
- profile sync UX: differences dialog, pending/synced/failed with last sync time, auto-retry, survives restart; never claims success on connect alone.
## Delivery
Single report: fixed / preserved / incomplete / versions / automated results / hardware checklist (both devices together; pairing items 1–10 of the brief + 0.6.1 touch items + hybrid journey). Firmware first, then app. No flashing without approval. No battery hardware changes; charging safety not verified (HW-1).
