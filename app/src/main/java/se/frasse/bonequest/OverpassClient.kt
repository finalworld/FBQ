package se.frasse.bonequest

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.math.*

object OverpassClient {
    suspend fun generateBones(center: GeoPoint, radiusMeters: Int = 3000): List<Bone> = withContext(Dispatchers.IO) {
        val query = """
            [out:json][timeout:25];
            way(around:$radiusMeters,${center.latitude},${center.longitude})
              ["highway"~"^(footway|path|pedestrian|track)$"]
              ["access"!="private"];
            out geom;
        """.trimIndent()
        val encoded = URLEncoder.encode(query, "UTF-8")
        val connection = (URL("https://overpass-api.de/api/interpreter?data=$encoded").openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 30_000
            requestMethod = "GET"
            setRequestProperty("User-Agent", "FrassesBoneQuest/0.200 (Android test build)")
        }
        if (connection.responseCode !in 200..299) error("Overpass svarade ${connection.responseCode}")
        val json = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })

        // Densify every usable walking way. This gives enough candidates to create
        // several breadcrumb trails instead of one lonely distant bone.
        val candidates = mutableListOf<GeoPoint>()
        val elements = json.getJSONArray("elements")
        for (i in 0 until elements.length()) {
            val geometry = elements.getJSONObject(i).optJSONArray("geometry") ?: continue
            if (geometry.length() < 2) continue
            var previous = GeoPoint(
                geometry.getJSONObject(0).getDouble("lat"),
                geometry.getJSONObject(0).getDouble("lon")
            )
            candidates += previous
            for (j in 1 until geometry.length()) {
                val node = geometry.getJSONObject(j)
                val current = GeoPoint(node.getDouble("lat"), node.getDouble("lon"))
                val segmentLength = distanceMeters(previous.latitude, previous.longitude, current.latitude, current.longitude)
                val steps = max(1, (segmentLength / 55.0).roundToInt())
                for (step in 1..steps) {
                    val t = step.toDouble() / steps
                    candidates += GeoPoint(
                        previous.latitude + (current.latitude - previous.latitude) * t,
                        previous.longitude + (current.longitude - previous.longitude) * t
                    )
                }
                previous = current
            }
        }

        val usable = candidates
            .distinctBy { "%.5f_%.5f".format(java.util.Locale.US, it.latitude, it.longitude) }
            .filter {
                val d = distanceMeters(center.latitude, center.longitude, it.latitude, it.longitude)
                d in 120.0..radiusMeters.toDouble()
            }

        val picked = mutableListOf<GeoPoint>()

        // Eight directions around the player. Each direction tries to form a chain:
        // first lure nearby, then another bone roughly 250–350 m farther on.
        for (sector in 0 until 8) {
            val targetAngle = sector * 45.0
            var anchor = center
            var anchorRadius = 0.0
            repeat(4) { step ->
                val minStep = if (step == 0) 140.0 else 230.0
                val maxStep = if (step == 0) 270.0 else 380.0
                val choice = usable.asSequence()
                    .filter { candidate ->
                        val stepDistance = distanceMeters(anchor.latitude, anchor.longitude, candidate.latitude, candidate.longitude)
                        val radius = distanceMeters(center.latitude, center.longitude, candidate.latitude, candidate.longitude)
                        val angle = bearingDegrees(center, candidate)
                        stepDistance in minStep..maxStep &&
                            radius >= anchorRadius + (if (step == 0) 0.0 else 120.0) &&
                            angleDifference(angle, targetAngle) <= 35.0 &&
                            picked.all { distanceMeters(it.latitude, it.longitude, candidate.latitude, candidate.longitude) >= 170.0 }
                    }
                    .minByOrNull { candidate ->
                        val stepDistance = distanceMeters(anchor.latitude, anchor.longitude, candidate.latitude, candidate.longitude)
                        abs(stepDistance - if (step == 0) 210.0 else 300.0) + angleDifference(bearingDegrees(center, candidate), targetAngle) * 3.0
                    }
                if (choice != null) {
                    picked += choice
                    anchor = choice
                    anchorRadius = distanceMeters(center.latitude, center.longitude, choice.latitude, choice.longitude)
                }
            }
        }

        // Fill gaps so the player normally sees plenty of choices, while keeping
        // enough spacing that the map does not become one solid pile of icons.
        usable.shuffled().forEach { candidate ->
            if (picked.size >= 30) return@forEach
            if (picked.all { distanceMeters(it.latitude, it.longitude, candidate.latitude, candidate.longitude) >= 190.0 }) {
                picked += candidate
            }
        }

        picked.take(30).map { point ->
            Bone(
                id = "v0200_${"%.6f".format(java.util.Locale.US, point.latitude)}_${"%.6f".format(java.util.Locale.US, point.longitude)}",
                latitude = point.latitude,
                longitude = point.longitude
            )
        }
    }

    private fun bearingDegrees(from: GeoPoint, to: GeoPoint): Double {
        val lat1 = Math.toRadians(from.latitude)
        val lat2 = Math.toRadians(to.latitude)
        val dLon = Math.toRadians(to.longitude - from.longitude)
        val y = sin(dLon) * cos(lat2)
        val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (Math.toDegrees(atan2(y, x)) + 360.0) % 360.0
    }

    private fun angleDifference(a: Double, b: Double): Double {
        val raw = abs(a - b) % 360.0
        return min(raw, 360.0 - raw)
    }
}

fun distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
    val earth = 6_371_000.0
    val p1 = Math.toRadians(lat1)
    val p2 = Math.toRadians(lat2)
    val dp = Math.toRadians(lat2 - lat1)
    val dl = Math.toRadians(lon2 - lon1)
    val a = sin(dp / 2).pow(2) + cos(p1) * cos(p2) * sin(dl / 2).pow(2)
    return earth * 2 * atan2(sqrt(a), sqrt(1 - a))
}
