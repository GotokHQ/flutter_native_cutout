import 'dart:typed_data';

import 'native_cutout_platform_interface.dart';

/// Error codes for cutout operations.
enum CutoutErrorCode {
  /// The input image path is invalid or file doesn't exist.
  invalidInput,

  /// No subject/foreground was detected in the image.
  noSubjectFound,

  /// An error occurred during image processing.
  processingFailed,
}

/// Android segmentation backend used for background removal.
///
/// iOS always uses Apple Vision regardless of this value.
enum CutoutBackend {
  /// Legacy Android U2-Net backend.
  ///
  /// Kept for source compatibility with older callers and remote-config values.
  /// Current Android builds use [mlKitSubject] even if this value is requested.
  u2Net,

  /// Google ML Kit Subject Segmentation.
  ///
  /// Android downloads this as a Google Play services optional module. iOS
  /// ignores this value and always uses Apple Vision.
  mlKitSubject,
}

/// Options for the cutout operation.
class CutoutOptions {
  /// Segmentation backend to use on Android.
  ///
  /// Defaults to [CutoutBackend.mlKitSubject]. Current Android builds are
  /// MLKit-only; legacy [CutoutBackend.u2Net] requests are treated as ML Kit
  /// by the native Android implementation.
  final CutoutBackend backend;

  /// Whether to crop the result to the subject bounds.
  final bool cropToSubject;

  /// When true (default) the native side writes the PNG to the app cache
  /// directory and returns a file path ([CutoutFileSuccess]).
  ///
  /// When false, raw PNG bytes are returned ([CutoutBytesSuccess]). Note that
  /// bytes round-trip across the method channel and are then decoded for
  /// display, so a 4000×3000 PNG can push peak memory past 100 MB. Prefer the
  /// cache path unless you specifically need bytes in Dart.
  final bool writeToCache;

  /// Soft-edge feather applied to the alpha matte, in pixels.
  ///
  /// A small value (1-2) smooths the cutout edge to reduce jaggies/halos.
  /// `0` (default) leaves the platform matte untouched.
  final double featherRadius;

  /// Erodes (shrinks) the alpha matte by this many pixels before compositing.
  ///
  /// Useful to remove a 1px background-color fringe left by the segmenter.
  /// `0` (default) disables erosion.
  final int edgeErode;

  const CutoutOptions({
    this.backend = CutoutBackend.mlKitSubject,
    this.cropToSubject = false,
    this.writeToCache = true,
    this.featherRadius = 0,
    this.edgeErode = 0,
  });

  Map<String, dynamic> toMap() => {
    'backend': backend.name,
    'cropToSubject': cropToSubject,
    'writeToCache': writeToCache,
    'featherRadius': featherRadius,
    'edgeErode': edgeErode,
  };
}

/// Result of a cutout operation.
sealed class CutoutResult {
  const CutoutResult();
}

/// Successful cutout. Either file-backed or in-memory depending on
/// [CutoutOptions.writeToCache].
sealed class CutoutSuccess extends CutoutResult {
  /// Backend that actually produced the segmentation mask.
  final CutoutBackend backend;

  /// Backend requested by the caller.
  final CutoutBackend requestedBackend;

  /// True when a platform uses a fallback backend.
  ///
  /// The current Android implementation is MLKit-only, so this is normally
  /// false and is kept for compatibility with previous result metadata.
  final bool didFallback;

  const CutoutSuccess({
    this.backend = CutoutBackend.mlKitSubject,
    this.requestedBackend = CutoutBackend.mlKitSubject,
    this.didFallback = false,
  });
}

/// PNG was written to the app cache directory.
///
/// Use [path] with `Image.file`, or read the file as needed. The file lives
/// under the app cache directory and can be removed via
/// [NativeCutout.clearCache].
class CutoutFileSuccess extends CutoutSuccess {
  /// Absolute path to the PNG file on device storage.
  final String path;

  const CutoutFileSuccess(
    this.path, {
    super.backend,
    super.requestedBackend,
    super.didFallback,
  });
}

/// PNG returned directly as bytes.
class CutoutBytesSuccess extends CutoutSuccess {
  /// The processed image with transparent background as PNG bytes.
  final Uint8List pngBytes;

  const CutoutBytesSuccess(
    this.pngBytes, {
    super.backend,
    super.requestedBackend,
    super.didFallback,
  });
}

/// Failed cutout result containing error information.
class CutoutFailure extends CutoutResult {
  /// The error code indicating the type of failure.
  final CutoutErrorCode code;

  /// A human-readable error message.
  final String message;

  const CutoutFailure(this.code, this.message);

  @override
  String toString() => 'CutoutFailure($code: $message)';
}

/// Install state reported by Android model warm-up calls.
///
/// Android reports Google Play services optional module install states while
/// warming up ML Kit Subject Segmentation.
enum ModelInstallState {
  unknown,
  pending,
  downloading,
  downloadPaused,
  installing,
  completed,
  canceled,
  failed,
}

/// Snapshot of Android model warm-up progress.
///
/// Emitted on [NativeCutout.downloadProgress] while [NativeCutout.downloadModel]
/// is running. iOS never emits events (Vision framework is bundled).
class ModelDownloadProgress {
  /// Current install state reported by Play Services.
  final ModelInstallState state;

  /// Bytes downloaded so far, when Play services reports a known size.
  final int bytesDownloaded;

  /// Total bytes to download, or 0 when Play services does not report a size.
  final int totalBytes;

  /// Play Services error code when [state] is [ModelInstallState.failed].
  final int? errorCode;

  const ModelDownloadProgress({
    required this.state,
    required this.bytesDownloaded,
    required this.totalBytes,
    this.errorCode,
  });

  /// Fraction downloaded in `[0, 1]`, or `null` when total size is unknown.
  double? get fraction => totalBytes > 0 ? bytesDownloaded / totalBytes : null;

  @override
  String toString() =>
      'ModelDownloadProgress($state, $bytesDownloaded/$totalBytes'
      '${errorCode != null ? ', err=$errorCode' : ''})';
}

/// AI-powered background removal using native platform APIs.
///
/// Uses iOS Vision Framework (iOS 17+) and Android ML Kit Subject Segmentation.
class NativeCutout {
  NativeCutout._();

  /// Removes the background from an image, keeping only the foreground subject.
  ///
  /// [imagePath] is the absolute path to the image file on the device.
  /// [options] allows customizing the cutout behavior.
  ///
  /// Returns a [CutoutResult] which is one of:
  /// - [CutoutFileSuccess] with a path to a cached PNG (default)
  /// - [CutoutBytesSuccess] with PNG bytes when `options.writeToCache` is false
  /// - [CutoutFailure] with error code and message
  ///
  /// Example:
  /// ```dart
  /// final result = await NativeCutout.removeBackground('/path/to/image.jpg');
  /// switch (result) {
  ///   case CutoutFileSuccess(:final path):
  ///     // Image.file(File(path))
  ///     break;
  ///   case CutoutBytesSuccess(:final pngBytes):
  ///     // Image.memory(pngBytes)
  ///     break;
  ///   case CutoutFailure(:final code, :final message):
  ///     // Handle error
  ///     break;
  /// }
  /// ```
  static Future<CutoutResult> removeBackground(
    String imagePath, {
    CutoutOptions? options,
  }) {
    return NativeCutoutPlatform.instance.removeBackground(
      imagePath,
      options: options ?? const CutoutOptions(),
    );
  }

  /// Deletes every PNG written to the app cache directory by this plugin.
  ///
  /// Safe to call while no cutout is in flight. Returns true on success.
  static Future<bool> clearCache() {
    return NativeCutoutPlatform.instance.clearCache();
  }

  /// Checks if the native model/runtime is available and ready to use.
  ///
  /// On Android, this checks whether the Google Play services ML Kit Subject
  /// Segmentation optional module is available.
  ///
  /// On iOS, this always returns true as the Vision framework is built-in.
  static Future<bool> isModelAvailable({
    CutoutBackend backend = CutoutBackend.mlKitSubject,
  }) {
    return NativeCutoutPlatform.instance.isModelAvailable(backend: backend);
  }

  /// Warms up the model required for background removal.
  ///
  /// On Android, this requests the Google Play services optional Subject
  /// Segmentation module.
  ///
  /// On iOS, this is a no-op and always returns true.
  ///
  /// Returns true if the model is ready to use after this call.
  static Future<bool> downloadModel({
    CutoutBackend backend = CutoutBackend.mlKitSubject,
  }) {
    return NativeCutoutPlatform.instance.downloadModel(backend: backend);
  }

  /// Requests release of any platform-managed model resources.
  ///
  /// On Android, this asks Play services to release the optional Subject
  /// Segmentation module.
  ///
  /// On iOS, this is a no-op and always returns true.
  static Future<bool> clearModel({
    CutoutBackend backend = CutoutBackend.mlKitSubject,
  }) {
    return NativeCutoutPlatform.instance.clearModel(backend: backend);
  }

  /// Broadcast stream of model warm-up progress events while [downloadModel] runs.
  ///
  /// Android emits Play services module install progress. iOS returns an empty
  /// stream since the Vision framework is bundled with the system.
  static Stream<ModelDownloadProgress> get downloadProgress =>
      NativeCutoutPlatform.instance.downloadProgress;
}
