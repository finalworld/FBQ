package se.frasse.bonequest

import org.junit.Assert.*
import org.junit.Test

class GpsRulesTest {
    @Test fun accuracyMarginIsCapped(){assertEquals(30.0,GpsRules.interactionRadius(0f),0.0);assertEquals(45.0,GpsRules.interactionRadius(15f),0.0);assertEquals(55.0,GpsRules.interactionRadius(70f),0.0)}
    @Test fun usableFixRequiresAgeAndAccuracy(){assertTrue(GpsRules.isUsable(20f,5_000));assertFalse(GpsRules.isUsable(76f,5_000));assertFalse(GpsRules.isUsable(20f,90_001))}
    @Test fun worseFixDoesNotReplaceFreshGoodFix(){assertFalse(GpsRules.shouldReplaceFix(8f,2_000,45f,500));assertTrue(GpsRules.shouldReplaceFix(8f,20_000,35f,500));assertFalse(GpsRules.shouldReplaceFix(8f,2_000,10f,100_000))}
}
