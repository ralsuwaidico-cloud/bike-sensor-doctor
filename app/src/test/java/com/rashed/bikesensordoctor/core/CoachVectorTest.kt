package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/**
 * Runs every shared vector in testvectors/coach (one .txt per scenario) through the Kotlin CoachEngine.
 * The ESP32-S3 C++ port must pass the same files. Format: testvectors/coach/README.md.
 */
class CoachVectorTest {
    private fun vectorDir(): File {
        var d: File? = File(System.getProperty("user.dir")).absoluteFile
        while (d != null) { val v = File(d, "testvectors/coach"); if (v.isDirectory) return v; d = d.parentFile }
        fail("testvectors/coach not found above ${System.getProperty("user.dir")}"); throw IllegalStateException()
    }

    private fun config(line: String): CoachConfig {
        val kv = line.removePrefix("# config:").trim().split(Regex("\\s+")).filter { it.contains('=') }
            .associate { it.substringBefore('=') to it.substringAfter('=') }
        val d = CoachConfig()
        return d.copy(
            mode = kv["mode"]?.let { CoachMode.valueOf(it) } ?: CoachMode.ZONE2,
            ftpW = kv["ftp"]?.toInt() ?: 200, maxHr = kv["maxHr"]?.toInt() ?: 185,
            cadenceEnabled = (kv["cadence"] ?: "on") == "on",
            cadenceLow = kv["cadLow"]?.toInt() ?: 85, cadenceHigh = kv["cadHigh"]?.toInt() ?: 95,
            effortSource = when (kv["source"]) { "HR" -> EffortSource.HEART_RATE; "POWER" -> EffortSource.POWER; else -> EffortSource.AUTO },
            effortHoldMs = kv["hrHoldMs"]?.toLong() ?: d.effortHoldMs, powerHoldMs = kv["powerHoldMs"]?.toLong() ?: d.powerHoldMs,
            surgeHoldMs = kv["surgeHoldMs"]?.toLong() ?: d.surgeHoldMs, cadenceHoldMs = kv["cadHoldMs"]?.toLong() ?: d.cadenceHoldMs,
            minAlertMs = kv["minAlertMs"]?.toLong() ?: d.minAlertMs, sameRepeatMs = kv["sameRepeatMs"]?.toLong() ?: d.sameRepeatMs,
            keepRepeatMs = kv["keepRepeatMs"]?.toLong() ?: d.keepRepeatMs, smoothingMs = kv["smoothingMs"]?.toLong() ?: d.smoothingMs,
        )
    }

    data class Failure(val file: String, val tMs: Long, val expected: String, val actual: String, val reason: String)

    @Test fun allVectorsPass() {
        val files = vectorDir().listFiles { f -> f.name.endsWith(".txt") }!!.sortedBy { it.name }
        assertTrue("no vectors found", files.isNotEmpty())
        val failures = mutableListOf<Failure>()
        var asserted = 0
        for (f in files) {
            val lines = f.readLines()
            val cfg = lines.firstOrNull { it.startsWith("# config:") }?.let { config(it) } ?: CoachConfig(mode = CoachMode.ZONE2)
            val engine = CoachEngine(cfg)
            var lastT = -1L
            for (l in lines) {
                if (l.isBlank() || l.startsWith("#")) continue
                val p = l.split(",")
                val t = p[0].trim().toLong(); require(t > lastT) { "${f.name}: ticks must increase at t=$t" }; lastT = t
                val phase = Phase.valueOf(p[1].trim())
                fun sig(s: String) = s.trim().toIntOrNull()?.let { Signal(it, true) } ?: Signal.NONE
                val cue = engine.update(CoachInput(t, phase, sig(p[2]), sig(p[3]), sig(p[4])))
                val expect = p.getOrNull(5)?.trim().orEmpty()
                if (expect.isEmpty()) continue
                asserted++
                if (cue.type.name != expect) failures += Failure(f.name, t, expect, cue.type.name, cue.reason)
            }
        }
        if (failures.isNotEmpty()) {
            val msg = failures.take(25).joinToString("\n") { "${it.file} t=${it.tMs}: expected ${it.expected}, got ${it.actual} (${it.reason})" }
            fail("${failures.size} vector assertion(s) failed of $asserted:\n$msg")
        }
        println("coach vectors: ${files.size} files, $asserted assertions, all pass")
    }
}
