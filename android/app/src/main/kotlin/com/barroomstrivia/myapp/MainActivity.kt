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
                    "tick" -> {
                        // Distinct tension tick pulse with pitch stepping up (600Hz -> 1150Hz)
                        val freq = when (param) {
                            1 -> 1150.0
                            2 -> 960.0
                            3 -> 830.0
                            4 -> 720.0
                            5 -> 620.0
                            else -> 800.0
                        }
                        playPulseTone(freq, 65, 0.75)
                    }
                    "buzz", "time_up" -> {
                        // Classic authoritative game show buzzer (dissonant 150Hz + 158Hz)
                        playDissonantBuzzer(150.0, 158.0, 360, 0.85)
                    }
                    "correct" -> {
                        // Sparkling bell chime arpeggio: G5 -> B5 -> D6 -> G6
                        playToneSequence(
                            listOf(
                                Tone(783.99, 80, 0.6),
                                Tone(987.77, 80, 0.7),
                                Tone(1174.66, 80, 0.8),
                                Tone(1567.98, 250, 0.85)
                            )
                        )
                    }
                    "fanfare" -> {
                        // Victory celebration fanfare: C5 -> E5 -> G5 -> C6
                        playToneSequence(
                            listOf(
                                Tone(523.25, 120, 0.7),
                                Tone(659.25, 120, 0.75),
                                Tone(783.99, 140, 0.85),
                                Tone(1046.50, 420, 0.95)
                            )
                        )
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
