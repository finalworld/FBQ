package se.frasse.bonequest

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import com.google.android.gms.location.*

class LocationTracker(context: Context) {
    private val client = LocationServices.getFusedLocationProviderClient(context)
    private val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 4_000L)
        .setMinUpdateDistanceMeters(3f)
        .setWaitForAccurateLocation(false)
        .build()
    private var callback: LocationCallback? = null

    @SuppressLint("MissingPermission")
    fun start(onLocation: (Location) -> Unit) {
        if (callback != null) return
        callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                result.lastLocation?.let(onLocation)
            }
        }
        client.requestLocationUpdates(request, callback!!, android.os.Looper.getMainLooper())
    }

    fun stop() {
        callback?.let(client::removeLocationUpdates)
        callback = null
    }
}
