package se.frasse.bonequest

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GameNameRulesTest {
    @Test fun normalizesWhitespace() {
        assertEquals("Danne 7",GameNameRules.normalize("  Danne   7  "))
    }

    @Test fun acceptsSwedishLettersNumbersAndSpaces() {
        assertTrue(GameNameRules.isValidPlayerName("Frassevän 2"))
    }

    @Test fun rejectsPunctuationAndWrongLength() {
        assertFalse(GameNameRules.isValidPlayerName("AB"))
        assertFalse(GameNameRules.isValidPlayerName("Danne!"))
        assertFalse(GameNameRules.isValidPlayerName("123456789012345678901"))
    }
}
