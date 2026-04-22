import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_cutout.dart';
import 'native_cutout_platform_interface.dart';

/// An implementation of [NativeCutoutPlatform] that uses method channels.
class MethodChannelNativeCutout extends NativeCutoutPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('com.hugo/native_cutout');

  @override
  Future<CutoutResult> removeBackground(
    String imagePath, {
    required CutoutOptions options,
  }) async {
    try {
      final result = await methodChannel.invokeMethod<Uint8List>(
        'removeBackground',
        {
          'imagePath': imagePath,
          'options': options.toMap(),
        },
      );

      if (result == null) {
        return const CutoutFailure(
          CutoutErrorCode.processingFailed,
          'No result returned from native code',
        );
      }

      return CutoutSuccess(result);
    } on PlatformException catch (e) {
      final code = _parseErrorCode(e.code);
      return CutoutFailure(code, e.message ?? 'Unknown error');
    }
  }

  CutoutErrorCode _parseErrorCode(String code) {
    return switch (code) {
      'INVALID_INPUT' => CutoutErrorCode.invalidInput,
      'NO_SUBJECT' => CutoutErrorCode.noSubjectFound,
      _ => CutoutErrorCode.processingFailed,
    };
  }

  @override
  Future<bool> isModelAvailable() async {
    // iOS Vision framework is built-in, always available
    if (Platform.isIOS) return true;

    try {
      final result = await methodChannel.invokeMethod<bool>('isModelAvailable');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> downloadModel() async {
    // iOS Vision framework is built-in, no download needed
    if (Platform.isIOS) return true;

    try {
      final result = await methodChannel.invokeMethod<bool>('downloadModel');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
