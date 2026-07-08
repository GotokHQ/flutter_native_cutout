package com.hugo.native_cutout

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import com.google.android.gms.common.moduleinstall.InstallStatusListener
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate.InstallState
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.FloatBuffer
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.roundToInt

private const val TAG = "NativeCutoutPlugin"

private enum class CutoutBackend {
    MLKIT_SUBJECT
}

private fun CutoutBackend.wireName(): String = when (this) {
    CutoutBackend.MLKIT_SUBJECT -> "mlKitSubject"
}

class NativeCutoutPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var progressChannel: EventChannel
    private lateinit var context: android.content.Context
    private var progressSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val workerExecutor = Executors.newSingleThreadExecutor()

    private fun postSuccess(result: Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun postError(result: Result, code: String, message: String) {
        mainHandler.post { result.error(code, message, null) }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.hugo/native_cutout")
        channel.setMethodCallHandler(this)
        progressChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "com.hugo/native_cutout/download_progress"
        )
        progressChannel.setStreamHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        progressSink = events
    }

    override fun onCancel(arguments: Any?) {
        progressSink = null
    }

    @Suppress("UNUSED_PARAMETER")
    private fun parseBackend(value: String?): CutoutBackend = when (value) {
        else -> CutoutBackend.MLKIT_SUBJECT
    }

    private fun emitProgress(update: ModuleInstallStatusUpdate) {
        val sink = progressSink ?: return
        val progress = update.progressInfo
        val payload = mapOf(
            "state" to stateToString(update.installState),
            "bytesDownloaded" to (progress?.bytesDownloaded ?: 0L),
            "totalBytes" to (progress?.totalBytesToDownload ?: 0L),
            "errorCode" to update.errorCode,
        )
        mainHandler.post { sink.success(payload) }
    }

    private fun stateToString(state: Int): String = when (state) {
        InstallState.STATE_PENDING -> "pending"
        InstallState.STATE_DOWNLOADING -> "downloading"
        InstallState.STATE_DOWNLOAD_PAUSED -> "downloadPaused"
        InstallState.STATE_INSTALLING -> "installing"
        InstallState.STATE_COMPLETED -> "completed"
        InstallState.STATE_CANCELED -> "canceled"
        InstallState.STATE_FAILED -> "failed"
        else -> "unknown"
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isModelAvailable" -> checkModelAvailability(
                result
            )
            "downloadModel" -> downloadModel(
                result
            )
            "clearModel" -> clearModel(
                result
            )
            "clearCache" -> clearCache(result)
            "removeBackground" -> {
                val imagePath = call.argument<String>("imagePath")
                if (imagePath == null) {
                    result.error("INVALID_INPUT", "Missing imagePath argument", null)
                    return
                }

                @Suppress("UNCHECKED_CAST")
                val options = call.argument<Map<String, Any>>("options") ?: emptyMap()
                val cropToSubject = options["cropToSubject"] as? Boolean ?: false
                val writeToCache = options["writeToCache"] as? Boolean ?: true
                val featherRadius = (options["featherRadius"] as? Number)?.toFloat() ?: 0f
                val edgeErode = (options["edgeErode"] as? Number)?.toInt() ?: 0
                val backend = parseBackend(options["backend"] as? String)

                removeBackground(
                    imagePath,
                    backend,
                    cropToSubject,
                    writeToCache,
                    featherRadius,
                    edgeErode,
                    result
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun checkModelAvailability(result: Result) {
        val segmenter = SubjectSegmentation.getClient(
            SubjectSegmenterOptions.Builder().build()
        )
        val moduleInstallClient = ModuleInstall.getClient(context)

        moduleInstallClient.areModulesAvailable(segmenter)
            .addOnSuccessListener { response ->
                result.success(response.areModulesAvailable())
            }
            .addOnFailureListener { e ->
                result.error(
                    "CHECK_FAILED",
                    "Failed to check ML Kit model availability: ${e.message}",
                    null
                )
            }
    }

    private fun clearCache(result: Result) {
        workerExecutor.execute {
            try {
                val cacheDir = File(context.cacheDir, "native_cutout")
                if (cacheDir.exists()) cacheDir.deleteRecursively()
                postSuccess(result, true)
            } catch (e: Exception) {
                postError(result, "CACHE_CLEAR_FAILED", e.message ?: "Unknown error")
            }
        }
    }

    private fun clearModel(result: Result) {
        val segmenter = SubjectSegmentation.getClient(
            SubjectSegmenterOptions.Builder().build()
        )
        val moduleInstallClient = ModuleInstall.getClient(context)

        moduleInstallClient.releaseModules(segmenter)
            .addOnSuccessListener {
                result.success(true)
            }
            .addOnFailureListener { e ->
                result.error("CLEAR_FAILED", "Failed to clear ML Kit model: ${e.message}", null)
            }
    }

    private fun downloadModel(result: Result) {
        val segmenter = SubjectSegmentation.getClient(
            SubjectSegmenterOptions.Builder().build()
        )
        val moduleInstallClient = ModuleInstall.getClient(context)
        val listener = InstallStatusListener { update -> emitProgress(update) }

        val moduleInstallRequest = ModuleInstallRequest.newBuilder()
            .addApi(segmenter)
            .setListener(listener)
            .build()

        moduleInstallClient.installModules(moduleInstallRequest)
            .addOnSuccessListener {
                moduleInstallClient.unregisterListener(listener)
                result.success(true)
            }
            .addOnFailureListener { e ->
                moduleInstallClient.unregisterListener(listener)
                result.error(
                    "DOWNLOAD_FAILED",
                    "Failed to download ML Kit model: ${e.message}",
                    null
                )
            }
    }

    private fun removeBackground(
        imagePath: String,
        backend: CutoutBackend,
        cropToSubject: Boolean,
        writeToCache: Boolean,
        featherRadius: Float,
        edgeErode: Int,
        result: Result
    ) {
        workerExecutor.execute {
            val file = File(imagePath)
            if (!file.exists()) {
                postError(result, "INVALID_INPUT", "File does not exist: $imagePath")
                return@execute
            }

            val originalBitmap = BitmapFactory.decodeFile(imagePath)
            if (originalBitmap == null) {
                postError(result, "INVALID_INPUT", "Could not decode image: $imagePath")
                return@execute
            }

            val bitmap = fixOrientation(imagePath, originalBitmap)

            try {
                Log.d(
                    TAG,
                    "removeBackground start: requestedBackend=$backend, " +
                        "image=${bitmap.width}x${bitmap.height}, cropToSubject=$cropToSubject, " +
                        "writeToCache=$writeToCache, featherRadius=$featherRadius, edgeErode=$edgeErode"
                )
                val effectiveBackend = CutoutBackend.MLKIT_SUBJECT
                val segmentation = segmentWithMlKit(bitmap)
                val mask = segmentation.mask

                val hasSubject = segmentation.peakConfidence > 0.1f
                Log.d(
                    TAG,
                    "removeBackground segmented: requestedBackend=$backend, " +
                        "effectiveBackend=$effectiveBackend, mask=${segmentation.width}x${segmentation.height}, " +
                        "peakConfidence=${segmentation.peakConfidence}, hasSubject=$hasSubject"
                )

                if (!hasSubject) {
                    bitmap.recycle()
                    if (bitmap != originalBitmap) originalBitmap.recycle()
                    postError(result, "NO_SUBJECT", "No foreground subject detected in image")
                    return@execute
                }

                val resultBitmap = applyMask(
                    bitmap,
                    mask,
                    segmentation.width,
                    segmentation.height,
                    cropToSubject,
                    featherRadius,
                    edgeErode
                )
                bitmap.recycle()
                if (bitmap != originalBitmap) originalBitmap.recycle()

                if (resultBitmap == null) {
                    postError(result, "PROCESSING_FAILED", "Failed to apply mask")
                    return@execute
                }
                Log.d(
                    TAG,
                    "removeBackground composited: effectiveBackend=$effectiveBackend, " +
                        "output=${resultBitmap.width}x${resultBitmap.height}, writeToCache=$writeToCache"
                )

                if (writeToCache) {
                    try {
                        val cacheDir = File(context.cacheDir, "native_cutout").apply { mkdirs() }
                        val outFile = File(cacheDir, "cutout_${UUID.randomUUID()}.png")
                        outFile.outputStream().use { os ->
                            resultBitmap.compress(Bitmap.CompressFormat.PNG, 100, os)
                        }
                        resultBitmap.recycle()
                        postSuccess(
                            result,
                            successPayload(
                                requestedBackend = backend,
                                effectiveBackend = effectiveBackend,
                                path = outFile.absolutePath
                            )
                        )
                    } catch (e: Exception) {
                        resultBitmap.recycle()
                        postError(result, "PROCESSING_FAILED", "Failed to write PNG to cache: ${e.message}")
                    }
                } else {
                    val outputStream = ByteArrayOutputStream()
                    resultBitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
                    resultBitmap.recycle()
                    postSuccess(
                        result,
                        successPayload(
                            requestedBackend = backend,
                            effectiveBackend = effectiveBackend,
                            pngBytes = outputStream.toByteArray()
                        )
                    )
                }
            } catch (e: NoSubjectException) {
                bitmap.recycle()
                if (bitmap != originalBitmap) originalBitmap.recycle()
                postError(result, "NO_SUBJECT", e.message ?: "No foreground subject detected in image")
            } catch (e: Exception) {
                bitmap.recycle()
                if (bitmap != originalBitmap) originalBitmap.recycle()
                postError(result, "PROCESSING_FAILED", "Segmentation failed: ${e.message}")
            }
        }
    }

    private fun successPayload(
        requestedBackend: CutoutBackend,
        effectiveBackend: CutoutBackend,
        path: String? = null,
        pngBytes: ByteArray? = null
    ): Map<String, Any?> {
        return mapOf(
            "path" to path,
            "pngBytes" to pngBytes,
            "requestedBackend" to requestedBackend.wireName(),
            "backend" to effectiveBackend.wireName(),
            "didFallback" to (requestedBackend != effectiveBackend)
        )
    }

    private fun segmentWithMlKit(bitmap: Bitmap): SegmentationMask {
        Log.d(TAG, "ML Kit segmentation requested")
        val options = SubjectSegmenterOptions.Builder()
            .enableForegroundConfidenceMask()
            .build()
        val segmenter = SubjectSegmentation.getClient(options)

        return try {
            val moduleInstallClient = ModuleInstall.getClient(context)
            val modulesAvailable = Tasks.await(
                moduleInstallClient.areModulesAvailable(segmenter)
            ).areModulesAvailable()

            if (!modulesAvailable) {
                throw IllegalStateException("ML Kit optional subject segmentation module is not available")
            }
            Log.d(TAG, "ML Kit optional subject segmentation module is available")

            val inputImage = InputImage.fromBitmap(bitmap, 0)
            val segmentationResult = Tasks.await(segmenter.process(inputImage))
            val mask = segmentationResult.foregroundConfidenceMask
                ?: throw NoSubjectException("No foreground mask generated")

            val size = bitmap.width * bitmap.height
            val raw = FloatArray(size)
            var max = 0f
            mask.rewind()
            for (i in raw.indices) {
                if (!mask.hasRemaining()) break
                val value = mask.get().coerceIn(0f, 1f)
                raw[i] = value
                if (value > max) max = value
            }

            SegmentationMask(
                FloatBuffer.wrap(raw),
                bitmap.width,
                bitmap.height,
                peakConfidence = max
            )
        } finally {
            segmenter.close()
        }
    }

    private fun applyMask(
        bitmap: Bitmap,
        mask: FloatBuffer,
        maskWidth: Int,
        maskHeight: Int,
        cropToSubject: Boolean,
        featherRadius: Float,
        edgeErode: Int
    ): Bitmap? {
        val width = bitmap.width
        val height = bitmap.height

        // Read the confidence mask into a float array.
        mask.rewind()
        val maskArray = FloatArray(maskWidth * maskHeight)
        mask.get(maskArray)

        // Optional edge refinement on the confidence values (separable filters).
        if (edgeErode > 0) {
            erodeMask(maskArray, maskWidth, maskHeight, edgeErode)
        }
        if (featherRadius > 0f) {
            blurMask(maskArray, maskWidth, maskHeight, featherRadius.roundToInt().coerceAtLeast(1))
        }

        // Build an ARGB mask bitmap whose alpha carries the confidence, while
        // tracking subject bounds for optional cropping.
        var minX = maskWidth
        var minY = maskHeight
        var maxX = 0
        var maxY = 0
        var hasSubject = false
        val maskPixels = IntArray(maskWidth * maskHeight)
        for (i in maskArray.indices) {
            val alpha = (maskArray[i] * 255f).roundToInt().coerceIn(0, 255)
            maskPixels[i] = alpha shl 24
            if (alpha > 10) {
                hasSubject = true
                val x = i % maskWidth
                val y = i / maskWidth
                if (x < minX) minX = x
                if (y < minY) minY = y
                if (x > maxX) maxX = x
                if (y > maxY) maxY = y
            }
        }

        if (!hasSubject) return null

        val maskBitmap = Bitmap.createBitmap(maskWidth, maskHeight, Bitmap.Config.ARGB_8888)
        maskBitmap.setPixels(maskPixels, 0, maskWidth, 0, 0, maskWidth, maskHeight)

        // Scale the mask to the source size with bilinear filtering for smooth,
        // anti-aliased edges (vs. the previous nearest-neighbor sampling).
        val scaledMask = if (maskWidth == width && maskHeight == height) {
            maskBitmap
        } else {
            Bitmap.createScaledBitmap(maskBitmap, width, height, true).also {
                maskBitmap.recycle()
            }
        }

        // Composite: keep the source pixels only where the mask is opaque.
        val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.drawBitmap(bitmap, 0f, 0f, null)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            isFilterBitmap = true
            xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
        }
        canvas.drawBitmap(scaledMask, 0f, 0f, paint)
        scaledMask.recycle()

        if (!cropToSubject) {
            return output
        }

        // Map mask-space bounds to image space and crop.
        val sx = width.toFloat() / maskWidth
        val sy = height.toFloat() / maskHeight
        val cropL = (minX * sx).toInt().coerceIn(0, width - 1)
        val cropT = (minY * sy).toInt().coerceIn(0, height - 1)
        val cropR = ((maxX + 1) * sx).roundToInt().coerceIn(cropL + 1, width)
        val cropB = ((maxY + 1) * sy).roundToInt().coerceIn(cropT + 1, height)
        val cropW = cropR - cropL
        val cropH = cropB - cropT
        return if (cropW > 0 && cropH > 0) {
            val cropped = Bitmap.createBitmap(output, cropL, cropT, cropW, cropH)
            output.recycle()
            cropped
        } else {
            output
        }
    }

    /// Separable min-filter (erosion) on a single-channel mask in [0,1].
    /// Shrinks the subject slightly to remove a thin background fringe.
    private fun erodeMask(data: FloatArray, w: Int, h: Int, radius: Int) {
        if (radius <= 0) return
        val tmp = FloatArray(data.size)
        for (y in 0 until h) {
            val row = y * w
            for (x in 0 until w) {
                var m = 1f
                val from = (x - radius).coerceAtLeast(0)
                val to = (x + radius).coerceAtMost(w - 1)
                for (k in from..to) {
                    val v = data[row + k]
                    if (v < m) m = v
                }
                tmp[row + x] = m
            }
        }
        for (x in 0 until w) {
            for (y in 0 until h) {
                var m = 1f
                val from = (y - radius).coerceAtLeast(0)
                val to = (y + radius).coerceAtMost(h - 1)
                for (k in from..to) {
                    val v = tmp[k * w + x]
                    if (v < m) m = v
                }
                data[y * w + x] = m
            }
        }
    }

    /// Separable box blur (feather) on a single-channel mask in [0,1].
    private fun blurMask(data: FloatArray, w: Int, h: Int, radius: Int) {
        if (radius <= 0) return
        val tmp = FloatArray(data.size)
        for (y in 0 until h) {
            val row = y * w
            for (x in 0 until w) {
                var sum = 0f
                val from = (x - radius).coerceAtLeast(0)
                val to = (x + radius).coerceAtMost(w - 1)
                for (k in from..to) sum += data[row + k]
                tmp[row + x] = sum / (to - from + 1)
            }
        }
        for (x in 0 until w) {
            for (y in 0 until h) {
                var sum = 0f
                val from = (y - radius).coerceAtLeast(0)
                val to = (y + radius).coerceAtMost(h - 1)
                for (k in from..to) sum += tmp[k * w + x]
                data[y * w + x] = sum / (to - from + 1)
            }
        }
    }

    private fun fixOrientation(imagePath: String, bitmap: Bitmap): Bitmap {
        return try {
            val exif = ExifInterface(imagePath)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )

            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> {
                    matrix.postRotate(90f)
                    matrix.preScale(-1f, 1f)
                }
                ExifInterface.ORIENTATION_TRANSVERSE -> {
                    matrix.postRotate(-90f)
                    matrix.preScale(-1f, 1f)
                }
                else -> return bitmap
            }

            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } catch (e: Exception) {
            bitmap
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        progressChannel.setStreamHandler(null)
        progressSink = null
        workerExecutor.shutdown()
    }
}

private class NoSubjectException(message: String) : Exception(message)

private data class SegmentationMask(
    val mask: FloatBuffer,
    val width: Int,
    val height: Int,
    /** Highest foreground confidence; low values mean no subject. */
    val peakConfidence: Float
)
