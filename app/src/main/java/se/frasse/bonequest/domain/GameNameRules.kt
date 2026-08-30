package se.frasse.bonequest

object GameNameRules {
    private val allowed = Regex("^[\\p{L}\\p{N} ]+$")

    fun normalize(value: String): String = value.trim().replace(Regex("\\s+")," ")

    fun isValidPlayerName(value: String): Boolean {
        val normalized = normalize(value)
        return normalized.length in 3..20 && allowed.matches(normalized)
    }
}
