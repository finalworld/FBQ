package se.frasse.bonequest.walking

import kotlin.math.*

data class LocationSample(
    val latitude: Double,
    val longitude: Double,
    val accuracyMeters: Float,
    val elapsedRealtimeMillis: Long,
    val reportedSpeedMps: Float? = null
)

data class AcceptedSegment(val meters: Double,val from: LocationSample,val to: LocationSample)

class DistanceFilter(
    private val maximumAccuracyMeters: Float = 50f,
    private val maximumWalkingSpeedMps: Double = 12.0 / 3.6,
    private val minimumSegmentMeters: Double = 2.0,
    private val maximumGapMillis: Long = 120_000
) {
    private var previous: LocationSample? = null

    fun reset() { previous = null }

    fun add(sample: LocationSample): AcceptedSegment? {
        if (!sample.isSane()) return null
        val old = previous
        previous = sample
        if (old == null) return null
        val elapsed = sample.elapsedRealtimeMillis-old.elapsedRealtimeMillis
        if (elapsed<=0 || elapsed>maximumGapMillis) return null
        val meters = haversineMeters(old.latitude,old.longitude,sample.latitude,sample.longitude)
        if (meters<minimumSegmentMeters) return null
        val inferredSpeed = meters/(elapsed/1000.0)
        val reported = sample.reportedSpeedMps?.takeIf { it>=0 }
        if (inferredSpeed>maximumWalkingSpeedMps || (reported!=null && reported>maximumWalkingSpeedMps)) return null
        return AcceptedSegment(meters,old,sample)
    }

    private fun LocationSample.isSane(): Boolean =
        latitude in -90.0..90.0 && longitude in -180.0..180.0 &&
            accuracyMeters in 0.1f..maximumAccuracyMeters
}

internal fun haversineMeters(lat1: Double,lon1: Double,lat2: Double,lon2: Double): Double {
    val dLat=Math.toRadians(lat2-lat1); val dLon=Math.toRadians(lon2-lon1)
    val a=sin(dLat/2).pow(2)+cos(Math.toRadians(lat1))*cos(Math.toRadians(lat2))*sin(dLon/2).pow(2)
    return 6_371_000.0*2*asin(min(1.0,sqrt(a)))
}
