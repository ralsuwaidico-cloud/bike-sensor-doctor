package com.rashed.bikesensordoctor

import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.io.File

/**
 * End-to-end walk through the real app on an emulator (API 31, 720×1520 like the Nokia 5.3), driven through the
 * accessibility tree with UiAutomator — the same way a person taps. Screenshots of every screen are saved to the
 * app's external files dir and collected by CI. Rides use the SIMULATED sensor source; nothing here proves the
 * XDS meter or an HR strap.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class AppFlowTest {
    private lateinit var device: UiDevice
    private lateinit var ctx: Context
    /** On any failure, keep a screenshot of what the screen looked like. */
    @get:org.junit.Rule val watcher: org.junit.rules.TestWatcher = object : org.junit.rules.TestWatcher() {
        override fun failed(e: Throwable?, description: org.junit.runner.Description?) { runCatching { device.takeScreenshot(File(shots(), "FAIL_${description?.methodName}.png")); File(shots(), "FAIL_${description?.methodName}.txt").writeText(e?.stackTraceToString() ?: ""); device.dumpWindowHierarchy(File(shots(), "FAIL_${description?.methodName}_window.xml")) } }
    }
    private val pkg = "com.rashed.bikesensordoctor.debug"
    private val T = 8_000L

    private fun shots(): File = File(ctx.filesDir, "screens").apply { mkdirs() }   // pulled by CI with run-as
    private fun shot(name: String) { device.waitForIdle(1500); device.takeScreenshot(File(shots(), "$name.png")) }
    private fun tag(t: String): BySelector = By.res(t)
    private fun text(t: String): BySelector = By.text(t)
    /** Finds a node, scrolling the page (accessibility scroll actions, then swipes) if it is off-screen. */
    private fun find(sel: BySelector, timeout: Long = T): UiObject2 {
        var o = device.wait(Until.findObject(sel), minOf(timeout, 3000L))
        if (o == null) {
            val sc = device.findObject(By.scrollable(true))
            if (sc != null) {
                o = runCatching { sc.scrollUntil(androidx.test.uiautomator.Direction.DOWN, Until.findObject(sel)) }.getOrNull()
                if (o == null) o = runCatching { device.findObject(By.scrollable(true))?.scrollUntil(androidx.test.uiautomator.Direction.UP, Until.findObject(sel)) }.getOrNull()
            }
        }
        if (o == null) { repeat(4) { if (o == null) { swipe(up = true); o = device.wait(Until.findObject(sel), 700) } } }
        if (o == null) { repeat(5) { if (o == null) { swipe(up = false); o = device.wait(Until.findObject(sel), 700) } } }
        if (o == null && timeout > 3000) o = device.wait(Until.findObject(sel), timeout - 3000)
        assertNotNull("not found: $sel", o); return o!!
    }
    private fun swipe(up: Boolean) { val w = device.displayWidth / 2; val a = (device.displayHeight * 0.72).toInt(); val b = (device.displayHeight * 0.30).toInt(); if (up) device.swipe(w, a, w, b, 25) else device.swipe(w, b, w, a, 25); device.waitForIdle(800); Thread.sleep(350) }
    private fun tap(sel: BySelector, timeout: Long = T) {
        find(sel, timeout)
        // a node clipped at the bottom edge (behind the tab bar) must be scrolled fully into view before tapping
        val bottom = (0 until 3).firstNotNullOfOrNull { runCatching { find(sel, 2000).visibleBounds.bottom }.getOrNull() } ?: 0
        if (bottom > device.displayHeight * 0.80) { val w = device.displayWidth / 2; device.swipe(w, (device.displayHeight * 0.6).toInt(), w, (device.displayHeight * 0.35).toInt(), 25); device.waitForIdle(800); Thread.sleep(300) }
        retry { find(sel, 2000).click() }; device.waitForIdle(1000)
    }
    private fun top() { val sc = device.findObject(By.scrollable(true)); if (sc != null) runCatching { sc.fling(androidx.test.uiautomator.Direction.UP) }; repeat(2) { swipe(up = false) } }
    private fun visible(sel: BySelector, timeout: Long = 3000L) = runCatching { find(sel, timeout) }.isSuccess
    private fun has(sel: BySelector, timeout: Long = 2000L) = device.wait(Until.hasObject(sel), timeout)
    private fun scrollTo(sel: BySelector): UiObject2 = find(sel)
    private fun retry(times: Int = 4, block: () -> Unit) { var last: Throwable? = null; repeat(times) { try { block(); return } catch (e: Throwable) { last = e; Thread.sleep(400) } }; throw last!! }
    private fun launch() {
        // Launch through the shell (`am start`), not from the test process: Android 12 blocks activity starts from a
        // background app once its 10-second grace after leaving the foreground has passed, which made this launch
        // intermittently silent on a slow emulator (run 52). The shell is never subject to that restriction.
        device.executeShellCommand("am start -W -n $pkg/com.rashed.bikesensordoctor.ui.MainActivity")
        if (!device.wait(Until.hasObject(By.pkg(pkg).depth(0)), T)) {
            device.executeShellCommand("am start -W -n $pkg/com.rashed.bikesensordoctor.ui.MainActivity")
            device.wait(Until.hasObject(By.pkg(pkg).depth(0)), T)
        }
        // a system permission dialog (Nearby devices / location) would cover the app: allow it; the first cold start
        // on the emulator (font loading, class verification) can take a while, so wait for something of ours
        for (n in 0 until 40) {
            device.findObject(By.clickable(true).textContains("llow"))?.let { it.click(); device.waitForIdle() }
            device.findObject(By.clickable(true).text("While using the app"))?.let { it.click(); device.waitForIdle() }
            if (device.hasObject(By.res(java.util.regex.Pattern.compile("rider_.*|start_ride|start_onboarding|btn_start|next_page|confirm_profile")))) break
            Thread.sleep(500)
        }
    }

    @Before fun setUp() {
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        // the live dashboard never goes "idle" (it refreshes continuously): don't let every lookup wait 10 s for that
        androidx.test.uiautomator.Configurator.getInstance().waitForIdleTimeout = 800
        ctx = ApplicationProvider.getApplicationContext()
        device.pressHome()
    }

    @Test fun t01_firstLaunch_signIn_create_onboard_home() {
        launch()
        find(tag("rider_omar"), 15_000)         // sample riders are seeded on first launch
        shot("01_sign_in")
        find(tag("new_name")).text = "Rashed"
        tap(tag("create_btn"))
        find(tag("start_onboarding")); shot("02_welcome")
        tap(tag("start_onboarding"))
        // page 1: about you
        find(text("3+ yrs")); shot("03_page1")
        tap(text("3+ yrs")); tap(tag("next_page"))
        // page 2: goals
        tap(text("Endurance (Zone 2)")); shot("04_page2"); tap(text("90% of a ride in Zone 2")); tap(tag("next_page"))
        // page 3: routine
        find(text("3")); retry { device.findObjects(text("3")).first().click() }; device.waitForIdle(1000); retry { device.findObjects(text("4")).last().click() }; device.waitForIdle(1000); shot("05_page3"); tap(tag("next_page"))
        // page 4: zones (I know my numbers)
        tap(text("I know my numbers"))
        find(tag("num_maxHr")).text = "186"; find(tag("num_lthr")).text = "168"; device.waitForIdle()
        scrollTo(text("Tested"))
        retry { device.findObjects(text("Tested")).first().click() }; device.waitForIdle(1000)
        retry { device.findObjects(text("Tested")).last().click() }; device.waitForIdle(1000)
        tap(text("Don't know yet")); shot("06_page4"); scrollTo(tag("next_page")); tap(tag("next_page"))
        // page 5: prefs
        tap(text("On")); tap(text("Corrections")); shot("07_page5"); tap(tag("next_page"))
        // page 6: summary
        find(text("CONFIRMED"), 10_000); shot("08_profile"); scrollTo(tag("confirm_profile")); tap(tag("confirm_profile"))
        find(tag("start_ride")); shot("09_home")
        assertTrue(has(text("Riding as "), 3000))
    }

    @Test fun t02_club_board_profile_tabs_and_back() {
        launch()
        find(tag("start_ride"), 15_000)
        tap(text("CLUB")); find(tag("invite_code")); shot("10_club_not_member")
        find(tag("invite_code")).text = "DAWN-7Q2K"; device.waitForIdle(); tap(tag("join_btn"))
        find(text("Leave club"), 5000); shot("11_club_joined")
        tap(text("BOARD")); find(text("Weekly distance")); shot("12_board_week")
        tap(text("Climb")); find(text("Elevation this month")); shot("13_board_climb")
        tap(text("Z2 ★")); shot("14_board_z2")
        tap(text("CLUB")); tap(tag("member_layla")); find(text("COACHING IS PERSONAL")); shot("15_member_layla")
        device.pressBack(); find(text("Leave club"), 5000)   // back → club
        tap(text("ME")); find(tag("confirm_profile")); shot("16_me")
        device.pressBack(); find(tag("start_ride"))   // back from ME → Home
        tap(text("BOARD")); device.pressBack(); find(tag("start_ride"))   // back from board → Home
        device.pressBack()   // back on Home leaves the app
        assertTrue(device.wait(Until.gone(By.pkg(pkg).depth(0)), 5000))
    }

    @Test fun t03_switch_rider_isolates_profiles() {
        launch()
        find(tag("switch_rider"), 15_000); tap(tag("switch_rider"))
        find(tag("rider_omar")); shot("17_switch")
        tap(tag("rider_omar"))
        find(text("Riding as "), 8000); assertTrue("home shows Omar", has(text("Omar"), 2000)); shot("18_home_omar")
        assertTrue("Omar: Zone 2 endurance, 90 min", has(text("Zone 2 endurance"), 2000) && has(By.textStartsWith("90 min"), 2000))
        tap(tag("switch_rider")); tap(tag("rider_layla")); find(text("Riding as "), 8000); assertTrue("home shows Layla", has(text("Layla"), 2000)); shot("19_home_layla")
        assertTrue("Layla's FTP goal gives sweet-spot work", has(text("Sweet-spot intervals (3 × 10 min at 88–93% FTP)"), 3000) || has(text("Zone 2 endurance (easy day after weights)"), 500))
        // back to the created rider
        tap(tag("switch_rider")); find(tag("rider_omar")); val mine = device.findObjects(By.res(java.util.regex.Pattern.compile("rider_r.*"))).firstOrNull(); assertNotNull(mine); mine!!.click()
        find(text("Rashed"), 5000)
    }

    @Test fun t04_simulated_ride_full_session() {
        launch()
        find(tag("start_ride"), 15_000)
        // Settings → simulation at 30× (a 60-min planned ride plays in ~2 min)
        tap(text("⚙")); scrollTo(tag("open_simulation")); tap(tag("open_simulation"))
        tap(text("30×")); shot("20_simulation"); tap(tag("sim_start"))
        find(tag("btn_start")); shot("21_dashboard_idle")
        tap(tag("btn_start"))
        find(tag("btn_pause")); Thread.sleep(4000); shot("22_dashboard_warmup")
        assertNoScrollLive("warm-up")
        assertTrue("phase label", visible(By.textStartsWith("WARM-UP")) || visible(By.textStartsWith("MAIN")))
        // pause / resume
        tap(tag("btn_pause")); find(tag("btn_resume")); shot("23_paused"); tap(tag("btn_resume")); find(tag("btn_pause"))
        // wait for MAIN then COOL-DOWN (planned ride ends after 60 simulated minutes)
        top(); assertTrue("MAIN phase reached", device.wait(Until.hasObject(By.textStartsWith("MAIN")), 60_000))
        shot("25_dashboard_main")
        tap(tag("dash_details")); find(text("RIDE DETAILS")); shot("26_details"); device.pressBack(); find(tag("btn_pause"), 5000)
        top(); assertTrue("COOL-DOWN reached", device.wait(Until.hasObject(By.textStartsWith("COOL-DOWN")), 150_000))
        shot("27_dashboard_cooldown")
        // background + foreground must not lose the ride
        device.pressHome(); Thread.sleep(2000); launch(); find(tag("btn_pause"), 10_000)
        tap(tag("btn_finish")); tap(text("FINISH & SAVE"))   // the dialog is its own window: find it by its text
        find(tag("results_root"), 15_000); top(); shot("28_results_summary")
        find(text("HEART RATE")); shot("28b_results_hr"); find(text("AI COACH REVIEW")); shot("28c_results_coach")
        find(tag("save_post")); tap(text("Legs")); tap(text("Yes")); tap(tag("save_post"))
        find(tag("post_home")); shot("29_next_workout"); tap(tag("post_home"))
        find(tag("start_ride"))
        tap(text("HISTORY")); find(text("SIMULATED"), 5000); shot("30_history")
        device.pressBack(); find(tag("start_ride"))
    }

    /** The live screen is a fixed layout: nothing scrollable, and the essentials are on screen without any gesture. */
    private fun assertNoScrollLive(label: String) {
        assertTrue("$label: live screen present", has(tag("live_root"), 3000))
        assertTrue("$label: live screen must not scroll", !device.hasObject(By.scrollable(true)))
        for (t in listOf("live_speed", "live_dist", "live_time", "gauge_power", "gauge_hr", "gauge_cad", "live_targets", "coach_box", "coach_headline")) assertTrue("$label: $t visible without scrolling", has(tag(t), 1500))
        assertTrue("$label: a control visible", has(tag("btn_pause"), 500) || has(tag("btn_start"), 500) || has(tag("btn_resume"), 500))
        val box = device.findObject(tag("coach_box")); val ctl = device.findObject(By.res(java.util.regex.Pattern.compile("btn_(pause|start|resume)")))
        if (box != null && ctl != null) assertTrue("$label: coach box above the controls and inside the screen", box.visibleBounds.bottom <= ctl.visibleBounds.top && ctl.visibleBounds.bottom <= device.displayHeight)
    }

    @Test fun t04b_extremes_and_large_font_layout() {
        launch(); find(tag("start_ride"), 15_000)
        tap(text("⚙")); tap(tag("open_simulation")); tap(text("Layout test: 999 W · 199 bpm · 120 rpm")); tap(text("5×")); tap(tag("sim_start"))
        find(tag("btn_start")); tap(tag("btn_start")); find(tag("btn_pause")); Thread.sleep(6000)
        shot("33_live_extremes"); assertNoScrollLive("extremes")
        assertTrue("999 W shown", has(text("999"), 2000)); assertTrue("199 bpm shown", has(text("199"), 2000)); assertTrue("120 rpm shown", has(text("120"), 2000))
        // large system font: the fixed layout must still hold everything
        device.executeShellCommand("settings put system font_scale 1.3"); Thread.sleep(2500)
        launch(); find(tag("btn_pause"), 15_000); Thread.sleep(1500)
        shot("34_live_font_1_3"); assertNoScrollLive("font 1.3")
        device.executeShellCommand("settings put system font_scale 1.0"); Thread.sleep(2500)
        launch(); find(tag("btn_finish"), 15_000); tap(tag("btn_finish")); tap(text("FINISH & SAVE"))
        find(tag("results_root"), 15_000); if (has(tag("save_post"), 3000)) { tap(tag("save_post")); find(tag("post_home")) } ; tap(tag("post_home")); find(tag("start_ride"))
    }

    @Test fun t05_restart_keeps_data_and_settings_screens() {
        launch()
        // if an earlier test left a ride running, finish it first (a running ride re-opens on the dashboard by design)
        if (!has(tag("start_ride"), 4000) && visible(tag("btn_finish"), 4000)) { tap(tag("btn_finish")); tap(text("FINISH & SAVE")); if (has(tag("save_post"), 8000)) { tap(tag("save_post")); tap(tag("post_home")) } }
        find(tag("start_ride"), 15_000)
        assertTrue(has(text("Rashed"), 3000))
        tap(text("⚙")); shot("31_settings"); scrollTo(text("Advanced: Diagnose & Repair sensor"))
        device.pressBack(); find(tag("start_ride"))
        // dashboard without simulation: no Bluetooth on the emulator → notice shown, app alive; still a fixed, non-scrolling layout
        tap(tag("start_ride")); find(tag("btn_start")); shot("32_dashboard_no_bluetooth"); assertNoScrollLive("idle")
        // the emulator may or may not have a Bluetooth adapter: either the notice shows or the header reports the link state
        assertTrue(has(tag("bt_notice"), 3000) || visible(text("SCIENTIFIC COACH")))
        tap(tag("dash_home")); find(tag("start_ride"))
    }
}
