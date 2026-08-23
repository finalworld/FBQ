package se.frasse.bonequest

object GpsRules {
    const val BASE_INTERACTION_METERS=30.0
    const val MAX_ACCURACY_METERS=75f
    const val MAX_BONUS_METERS=25.0
    const val MAX_FIX_AGE_MILLIS=90_000L

    fun interactionRadius(accuracyMeters:Float):Double =
        BASE_INTERACTION_METERS+accuracyMeters.coerceIn(0f,MAX_BONUS_METERS.toFloat())

    fun isUsable(accuracyMeters:Float,ageMillis:Long):Boolean =
        accuracyMeters.isFinite()&&accuracyMeters in 0f..MAX_ACCURACY_METERS&&ageMillis in 0..MAX_FIX_AGE_MILLIS

    fun shouldReplaceFix(currentAccuracy:Float,currentAgeMillis:Long,newAccuracy:Float,newAgeMillis:Long):Boolean {
        if(!newAccuracy.isFinite()||newAccuracy<0||newAgeMillis<0||newAgeMillis>MAX_FIX_AGE_MILLIS)return false
        if(currentAgeMillis>15_000)return true
        return newAgeMillis<=currentAgeMillis+1_000&&newAccuracy<=currentAccuracy+10f
    }
}
