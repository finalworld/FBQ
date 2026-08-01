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
    private val maximumAccuracyMeters: Float = 35f,
    private val maximumWalkingSpeedMps: Double = 12.0 / 3.6,
    private val minimumSegmentMeters: Double = 3.0,
    private val maximumGapMillis: Long = 45_000,
    private val minimumGapMillis:Long = 2_000
) {
    private var previous: LocationSample? = null

    fun reset() { previous = null }

    fun add(sample: LocationSample): AcceptedSegment? {
        if (!sample.isSane()) return null
        val old = previous
        previous = sample
        if (old == null) return null
        val elapsed = sample.elapsedRealtimeMillis-old.elapsedRealtimeMillis
        if (elapsed<minimumGapMillis || elapsed>maximumGapMillis) return null
        val meters = haversineMeters(old.latitude,old.longitude,sample.latitude,sample.longitude)
        // GPS-punkter är cirklar, inte exakta koordinater. Rörelse som ryms i
        // den sammanlagda felmarginalen är sannolikt drift från en stilla mobil.
        val accuracyDeadZone=max(minimumSegmentMeters,(old.accuracyMeters+sample.accuracyMeters)*0.60)
        if (meters<accuracyDeadZone) return null
        val inferredSpeed = meters/(elapsed/1000.0)
        val reported = sample.reportedSpeedMps?.takeIf { it>=0 }
        if(reported!=null&&reported<0.30f&&meters<max(12.0,accuracyDeadZone*1.5))return null
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
