import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_cutout/native_cutout.dart';
import 'package:native_cutout/native_cutout_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelNativeCutout', () {
    late MethodChannelNativeCutout platform;
    late List<MethodCall> calls;

    setUp(() {
      platform = MethodChannelNativeCutout();
      calls = <MethodCall>[];
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, null);
    });

    test('removeBackground with writeToCache=false returns bytes', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            calls.add(call);
            return Uint8List.fromList([1, 2, 3]);
          });

      final result = await platform.removeBackground(
        '/tmp/photo.jpg',
        options: const CutoutOptions(cropToSubject: true, writeToCache: false),
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'removeBackground');
      expect(calls.single.arguments, <String, dynamic>{
        'imagePath': '/tmp/photo.jpg',
        'options': <String, dynamic>{
          'backend': 'mlKitSubject',
          'cropToSubject': true,
          'writeToCache': false,
          'featherRadius': 0.0,
          'edgeErode': 0,
        },
      });

      expect(result, isA<CutoutBytesSuccess>());
      expect((result as CutoutBytesSuccess).pngBytes, [1, 2, 3]);
      expect(result.backend, CutoutBackend.mlKitSubject);
      expect(result.requestedBackend, CutoutBackend.mlKitSubject);
      expect(result.didFallback, isFalse);
    });

    test('removeBackground with default options returns path', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            calls.add(call);
            return '/tmp/cache/cutout.png';
          });

      final result = await platform.removeBackground(
        '/tmp/photo.jpg',
        options: const CutoutOptions(),
      );

      expect(calls.single.arguments, <String, dynamic>{
        'imagePath': '/tmp/photo.jpg',
        'options': <String, dynamic>{
          'backend': 'mlKitSubject',
          'cropToSubject': false,
          'writeToCache': true,
          'featherRadius': 0.0,
          'edgeErode': 0,
        },
      });

      expect(result, isA<CutoutFileSuccess>());
      expect((result as CutoutFileSuccess).path, '/tmp/cache/cutout.png');
      expect(result.backend, CutoutBackend.mlKitSubject);
      expect(result.requestedBackend, CutoutBackend.mlKitSubject);
      expect(result.didFallback, isFalse);
    });

    test('parses structured native result backend metadata', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            calls.add(call);
            return <String, Object?>{
              'pngBytes': Uint8List.fromList([4, 5, 6]),
              'requestedBackend': 'mlKitSubject',
              'backend': 'u2Net',
              'didFallback': true,
            };
          });

      final result = await platform.removeBackground(
        '/tmp/photo.jpg',
        options: const CutoutOptions(
          backend: CutoutBackend.mlKitSubject,
          writeToCache: false,
        ),
      );

      expect(result, isA<CutoutBytesSuccess>());
      final success = result as CutoutBytesSuccess;
      expect(success.pngBytes, [4, 5, 6]);
      expect(success.requestedBackend, CutoutBackend.mlKitSubject);
      expect(success.backend, CutoutBackend.u2Net);
      expect(success.didFallback, isTrue);
    });

    test('maps NO_SUBJECT platform errors to noSubjectFound', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            throw PlatformException(code: 'NO_SUBJECT', message: 'No subject');
          });

      final result = await platform.removeBackground(
        '/tmp/photo.jpg',
        options: const CutoutOptions(),
      );

      expect(result, isA<CutoutFailure>());
      final failure = result as CutoutFailure;
      expect(failure.code, CutoutErrorCode.noSubjectFound);
      expect(failure.message, 'No subject');
    });

    test('returns processingFailed when native result is null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            platform.methodChannel,
            (call) async => null,
          );

      final result = await platform.removeBackground(
        '/tmp/photo.jpg',
        options: const CutoutOptions(),
      );

      expect(result, isA<CutoutFailure>());
      final failure = result as CutoutFailure;
      expect(failure.code, CutoutErrorCode.processingFailed);
    });

    test('clearModel forwards the method call', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            calls.add(call);
            return true;
          });

      final result = await platform.clearModel();

      expect(result, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'clearModel');
      expect(calls.single.arguments, <String, dynamic>{
        'backend': 'mlKitSubject',
      });
    });

    test('forwards ML Kit backend to native options', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            calls.add(call);
            return '/tmp/cache/mlkit-cutout.png';
          });

      await platform.removeBackground(
        '/tmp/photo.jpg',
        options: const CutoutOptions(backend: CutoutBackend.mlKitSubject),
      );

      expect(calls.single.arguments, <String, dynamic>{
        'imagePath': '/tmp/photo.jpg',
        'options': <String, dynamic>{
          'backend': 'mlKitSubject',
          'cropToSubject': false,
          'writeToCache': true,
          'featherRadius': 0.0,
          'edgeErode': 0,
        },
      });
    });

    test('clearCache forwards the method call', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            calls.add(call);
            return true;
          });

      final result = await platform.clearCache();

      expect(result, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'clearCache');
    });
  });
}
