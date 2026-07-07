import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_cutout.dart';
import 'native_cutout_platform_interface.dart';

/// An implementation of [NativeCutoutPlatform] that uses method channels.
class MethodChannelNativeCutout extends NativeCutoutPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('com.hugo/native_cutout');

  @visibleForTesting
  final progressEventChannel = const EventChannel(
    'com.hugo/native_cutout/download_progress',
  );

  @override
  Future<CutoutResult> removeBackground(
    String imagePath, {
    required CutoutOptions options,
  }) async {
    try {
      final result = await methodChannel.invokeMethod<Object>(
        'removeBackground',
        {'imagePath': imagePath, 'options': options.toMap()},
      );

      return _parseCutoutResult(result, options);
    } on PlatformException catch (e) {
      final code = _parseErrorCode(e.code);
      return CutoutFailure(code, e.message ?? 'Unknown error');
    }
  }

  CutoutResult _parseCutoutResult(Object? result, CutoutOptions options) {
    return switch (result) {
      String path => CutoutFileSuccess(
        path,
        backend: options.backend,
        requestedBackend: options.backend,
      ),
      Uint8List bytes => CutoutBytesSuccess(
        bytes,
        backend: options.backend,
        requestedBackend: options.backend,
      ),
      Map map => _parseStructuredCutoutResult(map, options),
      _ => const CutoutFailure(
        CutoutErrorCode.processingFailed,
        'No result returned from native code',
      ),
    };
  }

  CutoutResult _parseStructuredCutoutResult(Map map, CutoutOptions options) {
    final data = map.cast<Object?, Object?>();
    final requestedBackend = _parseBackend(
      data['requestedBackend'],
      fallback: options.backend,
    );
    final backend = _parseBackend(data['backend'], fallback: requestedBackend);
    final didFallback =
        data['didFallback'] as bool? ?? backend != requestedBackend;

    final path = data['path'];
    if (path is String) {
      return CutoutFileSuccess(
        path,
        backend: backend,
        requestedBackend: requestedBackend,
        didFallback: didFallback,
      );
    }

    final pngBytes = data['pngBytes'];
    if (pngBytes is Uint8List) {
      return CutoutBytesSuccess(
        pngBytes,
        backend: backend,
        requestedBackend: requestedBackend,
        didFallback: didFallback,
      );
    }

    return const CutoutFailure(
      CutoutErrorCode.processingFailed,
      'No cutout payload returned from native code',
    );
  }

  CutoutBackend _parseBackend(
    Object? value, {
    required CutoutBackend fallback,
  }) {
    return switch (value) {
      'u2Net' => CutoutBackend.u2Net,
      'mlKitSubject' => CutoutBackend.mlKitSubject,
      _ => fallback,
    };
  }

  CutoutErrorCode _parseErrorCode(String code) {
    return switch (code) {
      'INVALID_INPUT' => CutoutErrorCode.invalidInput,
      'NO_SUBJECT' => CutoutErrorCode.noSubjectFound,
      _ => CutoutErrorCode.processingFailed,
    };
  }

  @override
  Future<bool> isModelAvailable({
    CutoutBackend backend = CutoutBackend.u2Net,
  }) async {
    // iOS Vision framework is built-in, always available
    if (Platform.isIOS) return true;

    try {
      final result = await methodChannel.invokeMethod<bool>(
        'isModelAvailable',
        {'backend': backend.name},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> downloadModel({
    CutoutBackend backend = CutoutBackend.u2Net,
  }) async {
    // iOS Vision framework is built-in, no warm-up needed.
    if (Platform.isIOS) return true;

    try {
      final result = await methodChannel.invokeMethod<bool>('downloadModel', {
        'backend': backend.name,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> clearModel({CutoutBackend backend = CutoutBackend.u2Net}) async {
    // iOS Vision framework is built-in, no downloaded module to clear.
    if (Platform.isIOS) return true;

    try {
      final result = await methodChannel.invokeMethod<bool>('clearModel', {
        'backend': backend.name,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> clearCache() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('clearCache');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Stream<ModelDownloadProgress> get downloadProgress {
    if (Platform.isIOS) return const Stream.empty();
    return progressEventChannel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<Object?, Object?>();
      return ModelDownloadProgress(
        state: _parseState(map['state'] as String?),
        bytesDownloaded: (map['bytesDownloaded'] as num?)?.toInt() ?? 0,
        totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
        errorCode: (map['errorCode'] as num?)?.toInt(),
      );
    });
  }

  ModelInstallState _parseState(String? s) => switch (s) {
    'pending' => ModelInstallState.pending,
    'downloading' => ModelInstallState.downloading,
    'downloadPaused' => ModelInstallState.downloadPaused,
    'installing' => ModelInstallState.installing,
    'completed' => ModelInstallState.completed,
    'canceled' => ModelInstallState.canceled,
    'failed' => ModelInstallState.failed,
    _ => ModelInstallState.unknown,
  };
}
