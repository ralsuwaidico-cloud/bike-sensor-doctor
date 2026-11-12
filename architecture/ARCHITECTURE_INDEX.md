# Technical architecture index

Status: Current Draft · Version 0.1 · 12 Nov 2026 · Level 4
This is an entry page. The documents stay where they are, next to the code they describe. Nothing was moved.

Branch key: **rel** = `ios/checkpoint-f-ride` · **hw** = `docs/hardware-handover`.

## A. iPhone app (central authority) — rel

| Subject | Document | Notes |
|---|---|---|
| Data ownership (who records what; Apple Health rules) | `ios/OWNERSHIP.md` | Approved rules — do not change without impact assessment |
| Device-independent integration | `ios/INTEGRATION_ARCHITECTURE.md` | Owner directive 8 Nov |
| Engine interface used by screens | `ios/ENGINE_API_RC3.md` | |
| Data integrity, provenance, migrations | `ios/S20_DATA_INTEGRITY.md`, `ios/ENGINE_SIDE_EFFECTS_AUDIT.md` | |
| Coach rules as implemented (rules-based) | `ios/ADAPTIVE_COACH.md`, `ios/BEHAVIOUR_CONTRACT.md`, `ios/SAFETY_CHANGES_RC3.md` | |
| Sensors and integrations | `docs/INTEGRATIONS.md` | |
| Diagnostics pipeline | `ios/PIPELINE_HEALTH.md`, `ios/DIAG_TRANSFER.md` | |
| Accounts / backend (optional) | `backend/supabase/README.md`, `docs/research/RESTORTRAIN_AND_BACKEND.md` | |
| CI, testing, release | `ios/CI_PROCESS.md`, `ios/CI_PIPELINE.md`, `ios/TEST_MATRIX.md`, `ios/RELEASE_CHECKLIST.md` | |
| Production design-system components | `ios/DESIGN_SYSTEM.md` | |

## B. Apple Watch app — rel

| Subject | Document |
|---|---|
| Live heart rate: Apple Watch → iPhone → BikeComputer | `ios/WATCH_PIPELINE.md` |
| Live heart rate by device family (research) | `docs/research/WEARABLES_LIVE_HR.md` |

## C. LILYGO detachable Cyclift Watch — separate hardware workstream

Status: design approved in part (design system A and information architecture B); screens C and prototype D awaiting
review; firmware stages recorded in the readiness documents. Firmware work, flashing and hardware changes need
separate authorisation. Evidence levels are stated in each document and are not upgraded here.

| Subject | Document | Location |
|---|---|---|
| Master brief | `CYCLIFT_HARDWARE_HANDOVER/02_LILYGO_WATCH_MASTER_BRIEF.md` | hw |
| Architecture | `watch/docs/ARCHITECTURE.md` | hw |
| Bluetooth protocol (Watch) | `watch/docs/BLE_PROTOCOL.md` | hw |
| Round layout, text sizes, buttons, faces | `watch/docs/ROUND_LAYOUT.md`, `TEXT_SIZES.md`, `BUTTONS.md`, `WATCH_FACES.md` | hw |
| Hardware audit and readiness | `watch/docs/HARDWARE_AUDIT.md`, `HARDWARE_READINESS.md` | hw |
| Design system, information architecture, screens | `hardware-design/UIUX_V3_DESIGN_SYSTEM_AND_IA.md` | project |
| 102-feature registry and cross-platform audit | `hardware-design/FEATURE_REGISTRY_102.md`, `CYCLIFT_WATCH_FEATURE_AUDIT.md` | project |
| Stage readiness and hardware validation record | `hardware-design/WATCH_STAGE2A_READINESS.md`, `WATCH_IMPLEMENTATION_READINESS.md` | project |
| Detachable concept, prototype plan, measurements | `hardware-design/DETACHABLE_SYSTEM_PHASE1.md`, `PROTOTYPE_P1_AND_TEST_PLAN.md`, `P1_MEASUREMENT_GUIDE_BOM_ACCEPTANCE.md` | project |

## D. Waveshare BikeComputer — separate hardware workstream (not legacy)

Status: firmware line 0.4.0–0.7.x with its own release notes; a 0.7.4 release candidate is described in the work-status
dashboard of 28 Oct. What is hardware-verified is stated per feature in the handover's implementation status; it is
not restated or upgraded here.

| Subject | Document | Location |
|---|---|---|
| Master brief and implementation status | `CYCLIFT_HARDWARE_HANDOVER/01_BIKECOMPUTER_MASTER_BRIEF.md`, `06_IMPLEMENTATION_STATUS.md` | hw |
| Firmware architecture and design decisions | `docs/DEVICE_ARCHITECTURE.md`, `docs/DEVICE_DESIGN_DECISIONS.md`, `docs/MIGRATION_MATRIX.md` | rel |
| **BikeComputer Link protocol** | `firmware/waveshare/docs/BLE_LINK_PROTOCOL.md` (v1.2), `docs/LINK_V1_2_SPEC.md`, `ios/SYNC_PROPOSAL.md` | rel |
| Firmware releases | `firmware/waveshare/docs/FIRMWARE_0.6.0.md` … `FIRMWARE_0.7.3.md`, `CRASH_0.7.2.md`, `PARTITIONS_0.7.3.md` | rel |
| Power, Wi-Fi, charging | `firmware/waveshare/docs/POWER_0.5.0.md`, `POWER_FEASIBILITY.md`, `WIFI_0.6.0.md`, `CHARGE_ALERTS.md` | rel |
| Hardware risks and test log | `firmware/waveshare/docs/HW_RISK_REGISTER.md`, `HW_TEST_LOG_0.4.0.md` | rel |
| Power-meter protocol research (XDS / Branta) | `docs/PHASE2_PROTOCOL_RESEARCH.md`, `docs/PORTING_SPEC.md` | rel |

**The Watch protocol (C) and the BikeComputer Link protocol (D) are different documents for different devices.
Neither firmware nor protocol is assumed to be interchangeable.** (Conflict register 1.)

## E. Integration contracts across workstreams

| Subject | Document | Location |
|---|---|---|
| Integration contracts (handover) | `CYCLIFT_HARDWARE_HANDOVER/05_INTEGRATION_CONTRACTS.md` | hw |
| Workstream contracts and merge rules | `docs/briefs/CYCLIFT_CONTRACTS.md` | rel |
| Coach test vectors shared across platforms | `testvectors/coach/README.md` | rel |

## F. Android app (earlier line)

`docs/ARCHITECTURE_V2.md`, `docs/TEST_RESULTS*.md` (rel); `android-app/OPEN_ISSUES_PRIVACY_AND_SIGNING.md` (project).
Its place in the current ecosystem is not stated in the Project Instructions — listed as an open question.

## Limits

Paths under **hw** were taken from that branch's file list; only its design-system file was read in full for this index.
