package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. The decision logic for what to do after a BLE connection attempt
 * ends, extracted so it can be unit-tested without a real Bluetooth stack (the GATT callbacks can't run
 * off-device). GattManager calls [decide] and performs the returned action.
 *
 * Confirmed by the PC probe (2026-10-12): the sensor connects reliably when a single owner tears the old
 * connection down fully before retrying. The failures were Android-side, so the policy is:
 *   - user asked to disconnect            → STOP
 *   - attempt failed before ever READY    → first try autoConnect=true, then fall back to scheduled retry
 *   - dropped after a good session        → scheduled retry with back-off
 */
enum class RecoveryAction { STOP, TRY_AUTOCONNECT, SCHEDULE_RETRY }

object ConnectionPolicy {
    fun decide(userDisconnect: Boolean, everReady: Boolean, triedAutoConnect: Boolean): RecoveryAction = when {
        userDisconnect -> RecoveryAction.STOP
        everReady -> RecoveryAction.SCHEDULE_RETRY
        !triedAutoConnect -> RecoveryAction.TRY_AUTOCONNECT
        else -> RecoveryAction.SCHEDULE_RETRY
    }

    /** Exponential back-off used between scheduled retries, capped. */
    fun nextBackoffMs(currentMs: Long): Long = (currentMs * 2).coerceAtMost(16_000L).coerceAtLeast(1_000L)
}
