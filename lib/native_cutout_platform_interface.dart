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

  /// Checks if the ML model is available on Android.
  /// Always returns true on iOS (model is bundled with the system).
  Future<bool> isModelAvailable() {
    throw UnimplementedError('isModelAvailable() has not been implemented.');
  }

  /// Downloads the ML model on Android.
  /// No-op on iOS (model is bundled with the system).
  Future<bool> downloadModel() {
    throw UnimplementedError('downloadModel() has not been implemented.');
  }
}
