package com.rashed.bikesensordoctor.diag

enum class TestPhase { IDLE, STATIONARY, PEDALING, DONE }

/** Notification statistics collected during one phase of the still-vs-pedaling test (from real events only). */
data class PhaseResult(
    val durationS: Int,
    val notifyCountsByUuid: Map<String, Int>,
    val distinctPayloadsByUuid: Map<String, Int>,
    val sampleHexByUuid: Map<String, List<String>>,
) {
    val total: Int get() = notifyCountsByUuid.values.sum()
}

data class GuidedTestState(
    val phase: TestPhase = TestPhase.IDLE,
    val secondsLeft: Int = 0,
    val stationary: PhaseResult? = null,
    val pedaling: PhaseResult? = null,
    val verdict: String? = null,
)
