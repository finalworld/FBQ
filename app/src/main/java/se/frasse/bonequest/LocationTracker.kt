package se.frasse.bonequest

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import com.google.android.gms.location.*

class LocationTracker(context: Context) {
    private val client = LocationServices.getFusedLocationProviderClient(context)
    private val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 2_000L)
        .setMinUpdateDistanceMeters(1f)
        .setWaitForAccurateLocation(true)
        .setMaxUpdateDelayMillis(4_000L)
        .build()
    private var callback: LocationCallback? = null
    private var accepted:Location?=null

    @SuppressLint("MissingPermission")
    fun start(onLocation: (Location) -> Unit) {
        if (callback != null) return
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
