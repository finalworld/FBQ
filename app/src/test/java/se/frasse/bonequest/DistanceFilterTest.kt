package se.frasse.bonequest

import org.junit.Assert.*
import org.junit.Test
import se.frasse.bonequest.walking.DistanceFilter
import se.frasse.bonequest.walking.LocationSample

class DistanceFilterTest {
    private fun sample(lat:Double,lon:Double,time:Long,accuracy:Float=5f,speed:Float?=null)=
        LocationSample(lat,lon,accuracy,time,speed)

    @Test fun acceptsNormalWalkingSegment() {
        val filter=DistanceFilter(); assertNull(filter.add(sample(59.33,18.06,0)))
        val result=filter.add(sample(59.3301,18.06,10_000))
        assertNotNull(result); assertTrue(result!!.meters in 10.0..12.5)
    }

    @Test fun rejectsCarSpeedAndGpsJump() {
        val filter=DistanceFilter(); filter.add(sample(59.33,18.06,0))
        assertNull(filter.add(sample(59.34,18.06,10_000,5f,20f)))
    }

    @Test fun rejectsPoorAccuracyAndJitter() {
        val filter=DistanceFilter(); assertNull(filter.add(sample(59.33,18.06,0,80f)))
        assertNull(filter.add(sample(59.33,18.06,10_000)))
        assertNull(filter.add(sample(59.330001,18.06,20_000)))
    }

    @Test fun rejectsStaleGapWithoutBridgingIt() {
        val filter=DistanceFilter(); filter.add(sample(59.33,18.06,0))
        assertNull(filter.add(sample(59.3301,18.06,180_000)))
    }
}
