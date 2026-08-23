package se.frasse.bonequest

import org.junit.Assert.*
import org.junit.Test

class RpcFallbackTest {
    @Test fun recognizesPostgrestMissingFunction(){assertTrue(IllegalStateException("PGRST202 Could not find the function in the schema cache").isMissingRpc());assertFalse(IllegalStateException("TOO_FAR").isMissingRpc())}
}
