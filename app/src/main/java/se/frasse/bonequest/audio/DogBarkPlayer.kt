package se.frasse.bonequest.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin
import kotlin.random.Random

/** A tiny locally synthesized two-part dog bark; no network or licensed sample. */
object DogBarkPlayer {
    private const val SAMPLE_RATE = 22_050

    @Volatile
    private var playing = false

    fun play() {
        if (playing) return
        playing = true
        Thread({
            try {
                // Some physical Android devices reject a static AudioTrack at
                // this sample rate. Nothing in the proximity alert may ever
                // be allowed to terminate the app, so the complete audio
                // lifecycle (including Builder.build) is guarded here.
                runCatching {
                    val pcm = makeBark()
                    val minimumBuffer = AudioTrack.getMinBufferSize(
                        SAMPLE_RATE,
                        AudioFormat.CHANNEL_OUT_MONO,
                        AudioFormat.ENCODING_PCM_16BIT
                    )
                    check(minimumBuffer > 0)
                    val track = AudioTrack.Builder()
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                        )
                        .setAudioFormat(
                            AudioFormat.Builder()
                                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                .setSampleRate(SAMPLE_RATE)
                                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                                .build()
                        )
                        .setTransferMode(AudioTrack.MODE_STREAM)
                        .setBufferSizeInBytes(maxOf(minimumBuffer, pcm.size * 2))
                        .build()
                    try {
                        check(track.state == AudioTrack.STATE_INITIALIZED)
                        track.play()
                        track.write(pcm, 0, pcm.size, AudioTrack.WRITE_BLOCKING)
                    } finally {
                        runCatching { track.stop() }
                        runCatching { track.release() }
                    }
                }
            } finally {
                playing = false
            }
        }, "frasse-bark").start()
    }

    private fun makeBark(): ShortArray {
        val samples = ShortArray((SAMPLE_RATE * 0.58).toInt())
        val random = Random(400)
        var filteredNoise = 0.0
        for (i in samples.indices) {
            val t = i.toDouble() / SAMPLE_RATE
            val first = burstEnvelope(t, 0.015, 0.19)
            val second = burstEnvelope(t, 0.30, 0.18) * 0.78
            val envelope = first + second
            if (envelope <= 0.0001) continue
            filteredNoise = filteredNoise * 0.72 + (random.nextDouble() * 2 - 1) * 0.28
            val localT = if (t < 0.27) t else t - 0.285
            val fallingPitch = 245.0 - 95.0 * (localT / 0.20).coerceIn(0.0, 1.0)
            val throat = sin(2 * PI * fallingPitch * localT) +
                0.42 * sin(2 * PI * fallingPitch * 2.03 * localT)
            val sample = envelope * (0.61 * throat + 0.72 * filteredNoise)
            samples[i] = (sample.coerceIn(-1.0, 1.0) * Short.MAX_VALUE * 0.72).toInt().toShort()
        }
        return samples
    }

    private fun burstEnvelope(t: Double, start: Double, duration: Double): Double {
        val x = t - start
        if (x !in 0.0..duration) return 0.0
        val attack = (x / 0.018).coerceIn(0.0, 1.0)
        return attack * exp(-5.2 * x / duration)
    }
}
