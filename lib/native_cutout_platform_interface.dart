import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'native_cutout.dart';
import 'native_cutout_method_channel.dart';

abstract class NativeCutoutPlatform extends PlatformInterface {
  NativeCutoutPlatform() : super(token: _token);

  static final Object _token = Object();

  static NativeCutoutPlatform _instance = MethodChannelNativeCutout();

  static NativeCutoutPlatform get instance => _instance;

  static set instance(NativeCutoutPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Removes the background from an image at the given path.
  Future<CutoutResult> removeBackground(
    String imagePath, {
    required CutoutOptions options,
  }) {
    throw UnimplementedError('removeBackground() has not been implemented.');
  }

  /// Checks if the native model/runtime is available.
  /// Always returns true on bundled-model platforms.
  Future<bool> isModelAvailable() {
    throw UnimplementedError('isModelAvailable() has not been implemented.');
  }

  /// Warms up the native model when needed.
  /// No-op on bundled-model platforms.
  Future<bool> downloadModel() {
    throw UnimplementedError('downloadModel() has not been implemented.');
  }

  /// Requests release of platform-managed model resources.
  /// No-op when the model is bundled.
  Future<bool> clearModel() {
    throw UnimplementedError('clearModel() has not been implemented.');
  }

  /// Clears cached PNG files written by [removeBackground] when
  /// `writeToCache` was enabled.
  Future<bool> clearCache() {
    throw UnimplementedError('clearCache() has not been implemented.');
  }

  /// Model warm-up progress events.
  /// Always empty on iOS.
  Stream<ModelDownloadProgress> get downloadProgress {
    throw UnimplementedError('downloadProgress has not been implemented.');
  }
}
