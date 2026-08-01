package se.frasse.bonequest

data class GeoPoint(val latitude: Double, val longitude: Double)
data class Bone(val id: String, val latitude: Double, val longitude: Double, val type: Int = 0)
data class DirtPile(val id: String, val latitude: Double, val longitude: Double, val cost: Int = 10, val type: Int = 0)
data class PlayerStats(
    val displayName: String = "Frassevän",
    val totalKm: Double = 0.0,
    val totalBonesCollected: Long = 0,
    val totalDirtPilesOpened: Long = 0,
    val memberSince: Long = System.currentTimeMillis()
)

val BONE_VALUES = intArrayOf(1, 2, 3, 5, 8, 12, 20, 35, 60, 100, 175, 300)
fun localizedBoneName(context:android.content.Context,type:Int)=context.getString(intArrayOf(
    R.string.bone_name_0,R.string.bone_name_1,R.string.bone_name_2,R.string.bone_name_3,
    R.string.bone_name_4,R.string.bone_name_5,R.string.bone_name_6,R.string.bone_name_7,
    R.string.bone_name_8,R.string.bone_name_9,R.string.bone_name_10,R.string.bone_name_11
)[type.coerceIn(0,11)])
fun boneValue(type: Int): Int = BONE_VALUES[type.coerceIn(BONE_VALUES.indices)]
fun weightedBoneType(seed: Int): Int {
    val roll = Math.floorMod(seed, 10_000)
    return when {
        roll < 4200 -> 0; roll < 6500 -> 1; roll < 7900 -> 2; roll < 8750 -> 3
        roll < 9250 -> 4; roll < 9550 -> 5; roll < 9730 -> 6; roll < 9840 -> 7
        roll < 9910 -> 8; roll < 9960 -> 9; roll < 9990 -> 10; else -> 11
    }
}
