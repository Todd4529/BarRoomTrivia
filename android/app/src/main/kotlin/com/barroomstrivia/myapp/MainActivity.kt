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
            } else if (call.method == "exitApp") {
                result.success(true)
                runOnUiThread {
                    try {
                        moveTaskToBack(true)
                    } catch (_: Exception) {}
                    try {
                        finishAndRemoveTask()
                    } catch (_: Exception) {
                        try {
                            finishAffinity()
                        } catch (_: Exception) {
                            finish()
                        }
                    }
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        android.os.Process.killProcess(android.os.Process.myPid())
                        System.exit(0)
                    }, 250)
                }
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
                    "correct", "clapping_fanfare" -> {
                        playClappingCheeringSound(isGrandFanfare = false)
                    }
                    "fanfare" -> {
                        playClappingCheeringSound(isGrandFanfare = true)
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

    private fun playClappingCheeringSound(isGrandFanfare: Boolean = true) {
        val sampleRate = 44100
        val totalMs = if (isGrandFanfare) 3600 else 1650
        val totalSamples = (sampleRate * totalMs) / 1000
        val buffer = ShortArray(totalSamples)
        val random = java.util.Random(1337L)

        // LAYER 1: Realistic Multi-Person Acoustic Handclapping (palm-on-palm flesh impact) - Crowd Applause
        val numClappers = if (isGrandFanfare) 24 else 16
        for (p in 0 until numClappers) {
            val clapRateMs = 250 + (random.nextInt(120))
            var currentMs = (random.nextInt(220))
            val fBody = 370.0 + random.nextInt(110)
            val fCavity = 1000.0 + random.nextInt(300)
            val pVol = 0.45 + (random.nextDouble() * 0.35)

            while (currentMs < totalMs - 120) {
                val offset = (sampleRate * currentMs) / 1000
                val clapDurationMs = 45
                val clapSamples = (sampleRate * clapDurationMs) / 1000

                val roomEnv = if (currentMs < 300) {
                    currentMs.toDouble() / 300.0
                } else if (currentMs < (totalMs - 1100)) {
                    1.0
                } else {
                    Math.max(0.0, 1.0 - (currentMs - (totalMs - 1100)).toDouble() / 1000.0)
                }
                val clapGain = pVol * roomEnv * (0.75 + random.nextDouble() * 0.5)

                for (i in 0 until clapSamples) {
                    val bufIdx = offset + i
                    if (bufIdx >= totalSamples) break
                    val t = i.toDouble() / sampleRate

                    val snap = if (t < 0.008) (random.nextDouble() * 2.0 - 1.0) * Math.exp(-t * 650.0) * 0.5 else 0.0
                    val mainSlap = if (t >= 0.004) (random.nextDouble() * 2.0 - 1.0) * Math.exp(-(t - 0.004) * 140.0) * 0.7 else 0.0
                    val bodyThump = sin(2.0 * Math.PI * fBody * t) * Math.exp(-t * 180.0) * 0.4
                    val cavity = sin(2.0 * Math.PI * fCavity * t) * Math.exp(-t * 240.0) * 0.3

                    val sampleVal = ((snap + mainSlap + bodyThump + cavity) * clapGain * 0.16 * Short.MAX_VALUE).toInt()
                    val existing = buffer[bufIdx].toInt()
                    buffer[bufIdx] = (existing + sampleVal).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                }

                currentMs += clapRateMs + random.nextInt(30)
            }
        }

        // LAYER 2: Collective Crowd Vocal Roar - Crowd Cheering
        var noiseFilter = 0.0
        val roarSustain = if (isGrandFanfare) 1.8 else 0.8
        val roarDecay = if (isGrandFanfare) 1.5 else 0.7
        for (i in 0 until totalSamples) {
            val t = i.toDouble() / sampleRate
            val roarEnv = if (t < 0.28) {
                t / 0.28
            } else if (t < roarSustain) {
                1.0
            } else {
                Math.max(0.0, 1.0 - (t - roarSustain) / roarDecay)
            }
            if (roarEnv > 0.0) {
                val rawNoise = random.nextDouble() * 2.0 - 1.0
                noiseFilter = noiseFilter * 0.88 + rawNoise * 0.12

                val v1 = sin(2.0 * Math.PI * 650.0 * t) * noiseFilter * 0.5
                val v2 = sin(2.0 * Math.PI * 1250.0 * t) * noiseFilter * 0.35
                val wash = (noiseFilter * 0.6 + v1 + v2) * roarEnv * 0.15

                val sampleVal = (wash * Short.MAX_VALUE).toInt()
                val existing = buffer[i].toInt()
                buffer[i] = (existing + sampleVal).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            }
        }

        // LAYER 3: Multiple Vocal Shouts ("WOOO!", "YEAAAH!", "WHOO-HOO!")
        data class CheerVoice(val startMs: Int, val durationMs: Int, val f0: Double, val f1: Double, val fEnd: Double, val formants: List<Double>, val vol: Double)
        val voices = if (isGrandFanfare) listOf(
            CheerVoice(80, 1150, 230.0, 340.0, 280.0, listOf(680.0, 1300.0, 2500.0), 0.16),
            CheerVoice(180, 1350, 190.0, 270.0, 210.0, listOf(750.0, 1600.0, 2700.0), 0.17),
            CheerVoice(320, 950, 280.0, 410.0, 330.0, listOf(620.0, 1150.0, 2400.0), 0.14),
            CheerVoice(450, 1250, 165.0, 220.0, 180.0, listOf(580.0, 1050.0, 2200.0), 0.15)
        ) else listOf(
            CheerVoice(60, 850, 220.0, 310.0, 260.0, listOf(720.0, 1450.0, 2600.0), 0.15),
            CheerVoice(140, 950, 185.0, 250.0, 200.0, listOf(680.0, 1300.0, 2500.0), 0.16)
        )

        for (v in voices) {
            val offset = (sampleRate * v.startMs) / 1000
            val voiceSamples = (sampleRate * v.durationMs) / 1000

            for (i in 0 until voiceSamples) {
                val bufIdx = offset + i
                if (bufIdx >= totalSamples) break
                val sT = i.toDouble() / voiceSamples
                val t = i.toDouble() / sampleRate

                val pitch = v.f0 + (v.f1 - v.f0) * sin(sT * Math.PI * 0.85)
                val vibrato = sin(2.0 * Math.PI * 5.8 * t) * 4.5
                val instFreq = pitch + vibrato

                val ph = 2.0 * Math.PI * instFreq * t
                val glottal = sin(ph) * 0.5 + sin(ph * 2.0) * 0.25 + sin(ph * 3.0) * 0.12

                var vocalFormant = 0.0
                val weights = doubleArrayOf(0.5, 0.35, 0.2)
                for ((fIdx, fVal) in v.formants.withIndex()) {
                    val w = if (fIdx < weights.size) weights[fIdx] else 0.2
                    vocalFormant += sin(2.0 * Math.PI * fVal * t) * w
                }

                val breath = (random.nextDouble() * 2.0 - 1.0) * 0.18
                val amp = if (sT < 0.15) (sT / 0.15) else if (sT < 0.75) 1.0 else (1.0 - (sT - 0.75) / 0.25)
                val voice = (glottal * 0.45 + vocalFormant * glottal * 0.45 + breath) * amp * v.vol

                val sampleVal = (voice * Short.MAX_VALUE).toInt()
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
