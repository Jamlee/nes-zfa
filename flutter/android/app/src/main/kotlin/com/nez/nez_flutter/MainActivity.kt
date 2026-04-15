package com.nez.nez_flutter

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var audioTrack: AudioTrack? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Audio channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nez/audio").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val sampleRate = 44100
                        val bufferSize = AudioTrack.getMinBufferSize(
                            sampleRate,
                            AudioFormat.CHANNEL_OUT_MONO,
                            AudioFormat.ENCODING_PCM_16BIT
                        )
                        audioTrack = AudioTrack.Builder()
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
                            .setBufferSizeInBytes(bufferSize)
                            .setTransferMode(AudioTrack.MODE_STREAM)
                            .build()
                        audioTrack?.play()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", "Failed to start AudioTrack: ${e.message}", null)
                    }
                }
                "stop" -> {
                    try {
                        audioTrack?.stop()
                        audioTrack?.release()
                        audioTrack = null
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", "Failed to stop AudioTrack: ${e.message}", null)
                    }
                }
                "pushSamples" -> {
                    try {
                        val bytes = call.arguments as ByteArray
                        audioTrack?.write(bytes, 0, bytes.size)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", "Failed to push samples: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Storage channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nez/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "getFilesDir" -> {
                    result.success(filesDir.absolutePath)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
        super.onDestroy()
    }
}
