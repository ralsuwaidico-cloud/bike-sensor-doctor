package com.rashed.bikesensordoctor

import android.app.Application
import android.content.Context
import com.rashed.bikesensordoctor.ride.RideEngine

/** Holds the single RideEngine shared by the activity and the foreground service. */
class BikeApp : Application() {
    val engine: RideEngine by lazy { RideEngine(this) }

    companion object {
        fun engine(ctx: Context): RideEngine = (ctx.applicationContext as BikeApp).engine
    }
}
