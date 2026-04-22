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

/// Options for the cutout operation.
class CutoutOptions {
  /// Whether to crop the result to the subject bounds.
  final bool cropToSubject;

  const CutoutOptions({
    this.cropToSubject = false,
  });

  Map<String, dynamic> toMap() => {
        'cropToSubject': cropToSubject,
      };
}

/// Result of a cutout operation.
sealed class CutoutResult {
  const CutoutResult();
}

/// Successful cutout result containing the processed image as PNG bytes.
class CutoutSuccess extends CutoutResult {
  /// The processed image with transparent background as PNG bytes.
  final Uint8List pngBytes;

  const CutoutSuccess(this.pngBytes);
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
  /// Returns a [CutoutResult] which is either:
  /// - [CutoutSuccess] with PNG bytes of the image with transparent background
  /// - [CutoutFailure] with error code and message
  ///
  /// Example:
  /// ```dart
  /// final result = await NativeCutout.removeBackground('/path/to/image.jpg');
  /// switch (result) {
  ///   case CutoutSuccess(:final pngBytes):
  ///     // Use pngBytes to display or save the image
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

  /// Checks if the ML model is available and ready to use.
  ///
  /// On Android, the ML Kit subject segmentation model must be downloaded
  /// before use. Call [downloadModel] if this returns false.
  ///
  /// On iOS, this always returns true as the Vision framework is built-in.
  static Future<bool> isModelAvailable() {
    return NativeCutoutPlatform.instance.isModelAvailable();
  }

  /// Downloads the ML model required for background removal.
  ///
  /// On Android, this triggers the download of the ML Kit subject segmentation
  /// model from Google Play Services. The download happens in the background.
  ///
  /// On iOS, this is a no-op and always returns true.
  ///
  /// Returns true if the model is ready to use after this call.
  static Future<bool> downloadModel() {
    return NativeCutoutPlatform.instance.downloadModel();
  }
}
