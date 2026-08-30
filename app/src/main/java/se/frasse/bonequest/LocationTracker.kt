package se.frasse.bonequest

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import com.google.android.gms.location.*

internal object StartupLocationFix {
    @Volatile var location:Location?=null
}

class LocationTracker(context: Context) {
    private val client = LocationServices.getFusedLocationProviderClient(context)
    private val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 2_000L)
        .setMinUpdateDistanceMeters(1f)
        // Give the map the first usable fix immediately. A more accurate fix
        // replaces it continuously instead of blocking the whole game start.
        .setWaitForAccurateLocation(false)
        .setMaxUpdateDelayMillis(0L)
        .build()
    private var callback: LocationCallback? = null
    private var accepted:Location?=null

    @SuppressLint("MissingPermission")
    fun start(onLocation: (Location) -> Unit) {
        if (callback != null) return
        StartupLocationFix.location?.takeIf {
            android.os.SystemClock.elapsedRealtimeNanos()-it.elapsedRealtimeNanos<=30_000_000_000L
        }?.let{accepted=it;onLocation(it)}
        callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val now=android.os.SystemClock.elapsedRealtimeNanos()
                result.locations.sortedBy{it.elapsedRealtimeNanos}.forEach{candidate->
                    val newAge=((now-candidate.elapsedRealtimeNanos)/1_000_000).coerceAtLeast(0)
                    val current=accepted
                    val currentAge=current?.let{((now-it.elapsedRealtimeNanos)/1_000_000).coerceAtLeast(0)}?:Long.MAX_VALUE
                    if(current==null||GpsRules.shouldReplaceFix(current.accuracy,currentAge,candidate.accuracy,newAge)){
                        accepted=candidate;onLocation(candidate)
                    }
                }
            }
        }
        client.requestLocationUpdates(request, callback!!, android.os.Looper.getMainLooper())
    }

    fun stop() {
        callback?.let(client::removeLocationUpdates)
        callback = null
        accepted = null
    }
}
