package com.barroomstrivia.myapp

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import kotlin.math.sin

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.barroomstrivia/audio"
    private val audioExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "playSound") {
                val type = call.argument<String>("type") ?: "tick"
                val param = call.argument<Int>("param") ?: 0
                playTailoredSound(type, param)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun playTailoredSound(type: String, param: Int) {
        audioExecutor.execute {
            try {
                when (type) {
                    "question_start", "start" -> {
                        // Uplifting 3-tone game show chord stinger: C5 (523Hz), E5 (659Hz), G5 (784Hz)
                        playToneSequence(
                            listOf(
                                Tone(523.25, 90, 0.65),
                                Tone(659.25, 90, 0.70),
                                Tone(783.99, 220, 0.85)
                            )
                        )
                    }
                    "tick", "tick_tock", "ticktock" -> {
                        playTickTockSound(param)
                    }
                    "buzz", "time_up" -> {
                        // Classic authoritative game show buzzer (dissonant 150Hz + 158Hz)
                        playDissonantBuzzer(150.0, 158.0, 360, 0.85)
                    }
                    "correct", "clapping_fanfare", "fanfare" -> {
                        // Celebratory clapping fanfare sound with crowd applause & brass chords
                        playClappingFanfareSound()
                    }
                    else -> playPulseTone(800.0, 60, 0.6)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private data class Tone(val freq: Double, val durationMs: Int, val volume: Double)

    private fun playToneSequence(tones: List<Tone>) {
        val sampleRate = 44100
        var totalSamples = 0
        for (t in tones) {
            totalSamples += (sampleRate * t.durationMs) / 1000
        }
        val buffer = ShortArray(totalSamples)
        var offset = 0
        for (t in tones) {
            val count = (sampleRate * t.durationMs) / 1000
            val attack = Math.min(count / 10, 400)
            val decay = count - attack
            for (i in 0 until count) {
                val time = i.toDouble() / sampleRate
                val rawSine = sin(2.0 * Math.PI * t.freq * time)
                val env = if (i < attack) {
                    i.toDouble() / attack
                } else {
                    1.0 - ((i - attack).toDouble() / decay)
                }
                val sample = (rawSine * env * t.volume * Short.MAX_VALUE).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                buffer[offset + i] = sample.toShort()
            }
            offset += count
        }
        playBuffer(buffer, sampleRate)
    }

    private fun playPulseTone(freq: Double, durationMs: Int, volume: Double) {
        val sampleRate = 44100
        val count = (sampleRate * durationMs) / 1000
        val buffer = ShortArray(count)
        val attack = Math.min(count / 10, 300)
        val decay = count - attack
        for (i in 0 until count) {
            val time = i.toDouble() / sampleRate
            val sine = sin(2.0 * Math.PI * freq * time)
            val env = if (i < attack) {
                i.toDouble() / attack
            } else {
                1.0 - ((i - attack).toDouble() / decay)
            }
            val sample = (sine * env * volume * Short.MAX_VALUE).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            buffer[i] = sample.toShort()
        }
        playBuffer(buffer, sampleRate)
    }

    private fun playDissonantBuzzer(freq1: Double, freq2: Double, durationMs: Int, volume: Double) {
        val sampleRate = 44100
        val count = (sampleRate * durationMs) / 1000
        val buffer = ShortArray(count)
        val attack = Math.min(count / 20, 200)
        val decay = count - attack
        for (i in 0 until count) {
            val time = i.toDouble() / sampleRate
            val sine1 = sin(2.0 * Math.PI * freq1 * time)
            val sine2 = sin(2.0 * Math.PI * freq2 * time)
            val harmonic = sin(2.0 * Math.PI * (freq1 * 2.0) * time) * 0.3
            val combined = (sine1 * 0.5 + sine2 * 0.5 + harmonic) / 1.3
            val env = if (i < attack) {
                i.toDouble() / attack
            } else {
                1.0 - ((i - attack).toDouble() / decay)
            }
            val sample = (combined * env * volume * Short.MAX_VALUE).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            buffer[i] = sample.toShort()
        }
        playBuffer(buffer, sampleRate)
    }

    private fun playTickTockSound(param: Int) {
        val sampleRate = 44100
        val isTick = (param % 2 != 0) // Alternating grandfather / pendulum clock escapement
        val baseFreq = if (isTick) 1450.0 else 920.0
        val totalMs = 70
        val totalSamples = (sampleRate * totalMs) / 1000
        val buffer = ShortArray(totalSamples)
        val random = java.util.Random(param.toLong() * 31L + 7L)

        // 1. Sharp mechanical escapement click impulse (first 12ms)
        val clickSamples = (sampleRate * 12) / 1000
        for (i in 0 until clickSamples) {
            val t = i.toDouble() / sampleRate
            val noise = (random.nextDouble() * 2.0 - 1.0)
            val clickImpulse = noise * 0.45 * Math.exp(-t * 350.0)
            val resonance = sin(2.0 * Math.PI * (if (isTick) 2800.0 else 2000.0) * t) * Math.exp(-t * 220.0) * 0.4
            val sample = ((clickImpulse + resonance) * Short.MAX_VALUE).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            buffer[i] = sample.toShort()
        }

        // 2. Resonant wood/brass clock housing body tone (decaying in 28ms)
        val bodySamples = (sampleRate * 28) / 1000
        for (i in 0 until bodySamples) {
            val t = i.toDouble() / sampleRate
            val sine = sin(2.0 * Math.PI * baseFreq * t)
            val decay = Math.exp(-t * 110.0)
            val sampleVal = (sine * decay * 0.55 * Short.MAX_VALUE).toInt()
            val existing = buffer[i].toInt()
            buffer[i] = (existing + sampleVal).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        }

        // 3. Subtle escapement gear catch click at 36ms
        val recoilOffset = (sampleRate * 36) / 1000
        val recoilSamples = (sampleRate * 12) / 1000
        for (i in 0 until recoilSamples) {
            val idx = recoilOffset + i
            if (idx >= totalSamples) break
            val t = i.toDouble() / sampleRate
            val recoil = sin(2.0 * Math.PI * (baseFreq * 1.5) * t) * Math.exp(-t * 260.0) * 0.22
            val sample = (recoil * Short.MAX_VALUE).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            buffer[idx] = sample.toShort()
        }

        playBuffer(buffer, sampleRate)
    }

    private fun playClappingFanfareSound() {
        val sampleRate = 44100
        val totalMs = 1400
        val totalSamples = (sampleRate * totalMs) / 1000
        val buffer = ShortArray(totalSamples)
        val random = java.util.Random(1337L)

        // LAYER 1: Crowd Applause (18 staggered acoustic handclaps)
        val clapDelaysMs = intArrayOf(
            0, 40, 90, 140, 190, 250, 310, 380,
            450, 530, 610, 700, 800, 900, 1010, 1120, 1230, 1340
        )
        for ((idx, delayMs) in clapDelaysMs.withIndex()) {
            val offset = (sampleRate * delayMs) / 1000
            val clapDurationMs = 22
            val clapSamples = (sampleRate * clapDurationMs) / 1000
            val clapFreq = 1200.0 + ((idx % 5) * 220.0)
            val clapVol = 0.35 + ((idx % 3) * 0.08)

            for (i in 0 until clapSamples) {
                val bufIdx = offset + i
                if (bufIdx >= totalSamples) break
                val t = i.toDouble() / sampleRate
                val noise = (random.nextDouble() * 2.0 - 1.0)
                val clapWave = (noise * 0.7 + sin(2.0 * Math.PI * clapFreq * t) * 0.3) * Math.exp(-t * 140.0)
                val sampleVal = (clapWave * clapVol * 0.45 * Short.MAX_VALUE).toInt()
                val existing = buffer[bufIdx].toInt()
                buffer[bufIdx] = (existing + sampleVal).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            }
        }

        // LAYER 2: Celebratory Brass Fanfare Progression
        data class FanfareNote(val freqs: DoubleArray, val startMs: Int, val durationMs: Int, val volume: Double)
        val notes = listOf(
            FanfareNote(doubleArrayOf(392.00), 0, 120, 0.40),
            FanfareNote(doubleArrayOf(523.25), 110, 120, 0.42),
            FanfareNote(doubleArrayOf(659.25), 230, 140, 0.45),
            FanfareNote(doubleArrayOf(783.99), 360, 160, 0.48),
            // Triumphant Grand Finale Chord: C5 (523.25) + E5 (659.25) + G5 (783.99) + C6 (1046.50)
            FanfareNote(doubleArrayOf(523.25, 659.25, 783.99, 1046.50), 520, 850, 0.65)
        )

        for (fn in notes) {
            val offset = (sampleRate * fn.startMs) / 1000
            val noteSamples = (sampleRate * fn.durationMs) / 1000
            val attack = Math.min(noteSamples / 10, 800)
            val decay = noteSamples - attack

            for (i in 0 until noteSamples) {
                val bufIdx = offset + i
                if (bufIdx >= totalSamples) break
                val t = i.toDouble() / sampleRate
                val env = if (i < attack) {
                    i.toDouble() / attack
                } else {
                    1.0 - ((i - attack).toDouble() / decay)
                }

                var chordWave = 0.0
                for (freq in fn.freqs) {
                    val fundamental = sin(2.0 * Math.PI * freq * t)
                    val secondHarmonic = sin(4.0 * Math.PI * freq * t) * 0.35
                    val thirdHarmonic = sin(6.0 * Math.PI * freq * t) * 0.15
                    chordWave += (fundamental + secondHarmonic + thirdHarmonic)
                }
                chordWave /= fn.freqs.size

                val sampleVal = (chordWave * env * fn.volume * 0.55 * Short.MAX_VALUE).toInt()
                val existing = buffer[bufIdx].toInt()
                buffer[bufIdx] = (existing + sampleVal).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            }
        }

        playBuffer(buffer, sampleRate)
    }

    private fun playBuffer(buffer: ShortArray, sampleRate: Int) {
        val audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(buffer.size * 2)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()

        audioTrack.write(buffer, 0, buffer.size)
        audioTrack.play()
        val durationMs = (buffer.size * 1000L) / sampleRate
        Thread.sleep(durationMs + 20)
        audioTrack.release()
    }
}
