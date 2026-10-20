package com.rashed.bikesensordoctor.ride

import android.content.Context
import com.rashed.bikesensordoctor.core.RideFeedback
import com.rashed.bikesensordoctor.core.RiderAnswers
import java.io.File

/**
 * One rider account = one folder: profile answers, onboarding state, post-ride feedback, and the ride history.
 * Everything is local to the phone (no cloud account yet — the sign-in screen says so). Accounts never share
 * files, so one rider's rides, zones and coaching can never leak into another's.
 *
 * The rider created by the first update ([LEGACY_ID]) keeps the app's original settings store and "rides" folder,
 * so updating over the old version keeps every saved ride and setting.
 */
class Rider(
    val id: String,
    var name: String,
    var pin: String?,
    val answers: RiderAnswers,
    var completed: Boolean,
    var page: Int,
    val asked: MutableSet<String>,
    val feedback: MutableList<RideFeedback>,
    val createdMs: Long,
    val isSample: Boolean,
) {
    val initials: String get() = name.trim().split(Regex("\\s+")).mapNotNull { it.firstOrNull()?.uppercaseChar() }.joinToString("").take(2).ifEmpty { "?" }
}

class RiderStore(private val context: Context) {
    private val root = File(context.filesDir, "riders").apply { mkdirs() }
    private val sp = context.getSharedPreferences("bike_accounts", Context.MODE_PRIVATE)

    var activeId: String?
        get() = sp.getString("active", null)?.takeIf { dir(it).exists() }
        set(v) = sp.edit().putString("active", v).apply()

    /**
     * v0.12 Developer / Test mode (off by default). Only when ON do the fictional SAMPLE riders (Omar, Layla, Sami, Noor) exist in
     * the rider list, the club and the demo board. Real installs never see them; turning it off hides them again (their folders
     * stay, tagged sample=true, and are ignored everywhere).
     */
    var devMode: Boolean
        get() = sp.getBoolean("dev_mode", false)
        set(v) { sp.edit().putBoolean("dev_mode", v).apply(); if (v) DemoClub.seed(this) else if (activeId?.let { load(it)?.isSample } == true) activeId = null }

    fun dir(id: String): File = File(root, id)
    fun ridesDir(id: String): File = if (id == LEGACY_ID) File(context.filesDir, "rides") else File(dir(id), "rides")

    /** Real riders only, unless Developer / Test mode is on (then SAMPLE riders follow the real ones). */
    fun list(): List<Rider> = listAll().filter { !it.isSample || devMode }
    fun listAll(): List<Rider> = root.listFiles()?.filter { it.isDirectory }?.mapNotNull { load(it.name) }?.sortedWith(compareBy({ it.isSample }, { it.createdMs })) ?: emptyList()

    fun load(id: String): Rider? {
        val d = dir(id); val meta = File(d, "meta.txt"); if (!meta.exists()) return null
        return runCatching {
            val m = HashMap<String, String>()
            meta.readLines().forEach { l -> val i = l.indexOf('='); if (i > 0) m[l.substring(0, i)] = l.substring(i + 1) }
            val answers = File(d, "answers.txt").takeIf { it.exists() }?.let { RiderAnswers.restore(it.readText()) } ?: RiderAnswers()
            val fb = File(d, "feedback.txt").takeIf { it.exists() }?.readLines()?.mapNotNull { RideFeedback.restore(it) }?.toMutableList() ?: ArrayList()
            Rider(id, m["name"] ?: id, m["pin"]?.ifEmpty { null }, answers, m["completed"] == "true", m["page"]?.toIntOrNull() ?: 0,
                m["asked"]?.split(',')?.filter { it.isNotEmpty() }?.toMutableSet() ?: HashSet(), fb, m["created"]?.toLongOrNull() ?: 0L, m["sample"] == "true")
        }.getOrNull()
    }

    fun save(r: Rider) {
        val d = dir(r.id).apply { mkdirs() }
        File(d, "meta.txt").writeText("name=${r.name}\npin=${r.pin ?: ""}\ncompleted=${r.completed}\npage=${r.page}\nasked=${r.asked.joinToString(",")}\ncreated=${r.createdMs}\nsample=${r.isSample}\n")
        File(d, "answers.txt").writeText(r.answers.snapshot())
        File(d, "feedback.txt").writeText(r.feedback.joinToString("\n") { it.snapshot() })
    }

    fun create(name: String, pin: String?, isSample: Boolean = false, id: String? = null): Rider {
        val rid = id ?: ("r" + java.lang.Long.toString(System.currentTimeMillis(), 36) + (100..999).random())
        val r = Rider(rid, name.trim().ifEmpty { "Rider" }, pin?.ifEmpty { null }, RiderAnswers(), false, 0, HashSet(), ArrayList(), System.currentTimeMillis(), isSample)
        save(r); return r
    }

    fun delete(id: String) { if (id != LEGACY_ID) dir(id).deleteRecursively() else File(dir(id), "meta.txt").delete() }

    /**
     * First run after the update: an existing single-rider install becomes rider "Me" (its rides/settings stay where
     * they are). v0.12: no sample riders are created for a real installation — they exist only in Developer / Test mode.
     * An install that was seeded by an earlier version keeps its real riders; its sample folders are simply hidden.
     */
    fun migrateIfNeeded() {
        if (root.listFiles()?.any { it.isDirectory } == true) {
            if (activeId?.let { load(it)?.isSample } == true && !devMode) activeId = null   // never start the app as a hidden sample rider
            return
        }
        val legacyRides = File(context.filesDir, "rides")
        val legacyPrefs = context.getSharedPreferences("bike_computer", Context.MODE_PRIVATE)
        val hadApp = (legacyRides.listFiles()?.isNotEmpty() == true) || legacyPrefs.all.isNotEmpty()
        if (hadApp) {
            val me = create("Me", null, id = LEGACY_ID)
            activeId = me.id
        }
    }

    companion object { const val LEGACY_ID = "me" }
}
