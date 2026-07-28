package se.frasse.bonequest

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class GameRepository(context: Context) {
    private val prefs = context.getSharedPreferences("frasse_bone_quest", Context.MODE_PRIVATE)
    fun boneCount(): Int = prefs.getInt("bone_count", 0)
    fun addCollectedBones(amount: Int) = prefs.edit().putInt("bone_count", boneCount() + amount).apply()
    fun spendBones(amount: Int): Boolean { if (boneCount() < amount) return false; prefs.edit().putInt("bone_count", boneCount()-amount).apply(); return true }
    fun stats(): PlayerStats = PlayerStats(
        displayName = prefs.getString("display_name", "Frassevän") ?: "Frassevän",
        totalKm = java.lang.Double.longBitsToDouble(prefs.getLong("total_km", 0L)),
        totalBonesCollected = prefs.getLong("total_bones_collected", 0L),
        totalDirtPilesOpened = prefs.getLong("total_piles", 0L),
        memberSince = prefs.getLong("member_since", 0L).takeIf { it > 0 } ?: System.currentTimeMillis().also { prefs.edit().putLong("member_since", it).apply() }
    )
    fun addDistance(km: Double) { val s=stats(); prefs.edit().putLong("total_km", java.lang.Double.doubleToRawLongBits(s.totalKm+km)).apply() }
    fun setDisplayName(name:String) = prefs.edit().putString("display_name", name.take(24)).apply()
    fun loadBones(): List<Bone> = parseBones(prefs.getString("bones", "[]") ?: "[]")
    fun saveBones(bones: List<Bone>) { val a=JSONArray(); bones.forEach{a.put(JSONObject().put("id",it.id).put("lat",it.latitude).put("lon",it.longitude).put("type",it.type))}; prefs.edit().putString("bones",a.toString()).apply() }
    private fun parseBones(raw:String)=buildList { val a=JSONArray(raw); for(i in 0 until a.length()){ val o=a.getJSONObject(i); val id=o.getString("id"); add(Bone(id,o.getDouble("lat"),o.getDouble("lon"),o.optInt("type",weightedBoneType(id.hashCode())))) } }
    fun collectBones(ids: List<String>): Pair<List<Bone>,Int> { val current=loadBones(); val taken=current.filter{it.id in ids}; val reward=taken.sumOf{boneValue(it.type)}; saveBones(current.filterNot{it.id in ids}); if(reward>0){addCollectedBones(reward); prefs.edit().putLong("total_bones_collected",stats().totalBonesCollected+taken.size).apply()}; return loadBones() to reward }
    fun loadPiles(): List<DirtPile> { val a=JSONArray(prefs.getString("piles","[]")?:"[]"); return buildList{for(i in 0 until a.length()){val o=a.getJSONObject(i);add(DirtPile(o.getString("id"),o.getDouble("lat"),o.getDouble("lon"),o.optInt("cost",10),o.optInt("type",0)))}} }
    fun savePiles(piles:List<DirtPile>){val a=JSONArray();piles.forEach{a.put(JSONObject().put("id",it.id).put("lat",it.latitude).put("lon",it.longitude).put("cost",it.cost).put("type",it.type))};prefs.edit().putString("piles",a.toString()).apply()}
    fun openPile(id:String): Pair<List<DirtPile>,Bone?> { val piles=loadPiles(); val pile=piles.firstOrNull{it.id==id}?:return piles to null; if(!spendBones(pile.cost)) return piles to null; val rewardType=(Math.floorMod(id.hashCode(),5)).coerceAtLeast(1); val reward=Bone("reward-${System.nanoTime()}",pile.latitude,pile.longitude,rewardType); addCollectedBones(boneValue(reward.type)); prefs.edit().putLong("total_piles",stats().totalDirtPilesOpened+1).apply(); val updated=piles.filterNot{it.id==id};savePiles(updated);return updated to reward }
    fun generatedNear(point: GeoPoint): Boolean { val lat=prefs.getString("generated_lat",null)?.toDoubleOrNull()?:return false;val lon=prefs.getString("generated_lon",null)?.toDoubleOrNull()?:return false;return distanceMeters(point.latitude,point.longitude,lat,lon)<1800 }
    fun markGenerated(point:GeoPoint){prefs.edit().putString("generated_lat",point.latitude.toString()).putString("generated_lon",point.longitude.toString()).apply()}
}
