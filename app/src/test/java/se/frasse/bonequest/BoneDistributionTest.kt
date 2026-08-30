package se.frasse.bonequest

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BoneDistributionTest {
    @Test fun fallbackDistributionMatchesServerWeights() {
        val counts = IntArray(12)
        repeat(10_000) { counts[weightedBoneType(it)]++ }
        assertEquals(
            listOf(1700,1900,1700,1500,1100,800,500,350,220,130,70,30),
            counts.toList()
        )
        assertEquals(10_000,counts.sum())
        assertTrue(counts.take(3).sum() < 6_000)
    }
}
