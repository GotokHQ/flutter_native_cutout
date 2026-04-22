import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_cutout/native_cutout.dart';
import 'package:native_cutout/native_cutout_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeNativeCutoutPlatform extends NativeCutoutPlatform
    with MockPlatformInterfaceMixin {
  String? capturedImagePath;
  CutoutOptions? capturedOptions;
  bool clearModelCalled = false;
  bool clearCacheCalled = false;

  @override
  Future<CutoutResult> removeBackground(
    String imagePath, {
    required CutoutOptions options,
  }) async {
    capturedImagePath = imagePath;
    capturedOptions = options;
    return CutoutBytesSuccess(Uint8List(0));
  }

  @override
  Future<bool> clearModel() async {
    clearModelCalled = true;
    return true;
  }

  @override
  Future<bool> clearCache() async {
    clearCacheCalled = true;
    return true;
  }
}

void main() {
  group('NativeCutout', () {
    late NativeCutoutPlatform originalPlatform;
    late _FakeNativeCutoutPlatform fakePlatform;

    setUp(() {
      originalPlatform = NativeCutoutPlatform.instance;
      fakePlatform = _FakeNativeCutoutPlatform();
      NativeCutoutPlatform.instance = fakePlatform;
    });

    tearDown(() {
      NativeCutoutPlatform.instance = originalPlatform;
    });

    test('uses default CutoutOptions when none are provided', () async {
      await NativeCutout.removeBackground('/tmp/input.jpg');

      expect(fakePlatform.capturedImagePath, '/tmp/input.jpg');
      expect(fakePlatform.capturedOptions?.cropToSubject, isFalse);
      expect(fakePlatform.capturedOptions?.writeToCache, isTrue);
    });

    test('forwards custom CutoutOptions to the platform layer', () async {
      await NativeCutout.removeBackground(
        '/tmp/input.jpg',
        options: const CutoutOptions(
          cropToSubject: true,
          writeToCache: false,
        ),
      );

      expect(fakePlatform.capturedImagePath, '/tmp/input.jpg');
      expect(fakePlatform.capturedOptions?.cropToSubject, isTrue);
      expect(fakePlatform.capturedOptions?.writeToCache, isFalse);
    });

    test('forwards clearModel to the platform layer', () async {
      final result = await NativeCutout.clearModel();

      expect(result, isTrue);
      expect(fakePlatform.clearModelCalled, isTrue);
    });

    test('forwards clearCache to the platform layer', () async {
      final result = await NativeCutout.clearCache();

      expect(result, isTrue);
      expect(fakePlatform.clearCacheCalled, isTrue);
    });
  });
}
