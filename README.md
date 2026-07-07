# native_cutout

[![pub package](https://img.shields.io/pub/v/native_cutout.svg)](https://pub.dev/packages/native_cutout)
[![pub points](https://img.shields.io/pub/points/native_cutout)](https://pub.dev/packages/native_cutout/score)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue.svg)](https://pub.dev/packages/native_cutout)

English | [简体中文](README.zh-CN.md)

Native background removal for Flutter using platform image segmentation APIs.

`native_cutout` removes the background from a local image file and produces a transparent PNG — fully on-device, with no external API, no upload step, and no API keys.

| Home · model manager | Cutout result |
| :---: | :---: |
| <img src="https://raw.githubusercontent.com/xcc3641/flutter_native_cutout/main/images/1.png" width="320" alt="Home page with Android model manager" /> | <img src="https://raw.githubusercontent.com/xcc3641/flutter_native_cutout/main/images/2.png" width="320" alt="Cutout result with cropToSubject and writeToCache toggles" /> |

It is built on top of:

- **iOS**: Vision Framework (`VNGenerateForegroundInstanceMaskRequest`)
- **Android**: bundled U2-Net light model running through a native Android inference runtime by default, plus an opt-in ML Kit Subject Segmentation backend for comparison

## Features

- Fully **on-device** background removal
- Default **file-backed output** written to the app cache directory
- Optional **in-memory PNG bytes** output when you need bytes in Dart
- Native image processing on both iOS and Android
- Handles **EXIF orientation** before segmentation
- Optional subject-bound cropping via `CutoutOptions.cropToSubject`
- Cache management via `clearCache()`
- Android backend selection via `CutoutOptions.backend`
- Android model lifecycle helpers kept for API compatibility, with ML Kit module checks/downloads available when explicitly selected
- Simple Dart API with typed success/failure results

## Platform support

| Platform | Engine | Minimum version | Notes |
| --- | --- | --- | --- |
| iOS | Vision Framework | iOS 13.0 (compile) / iOS 17.0 (runtime) | Requires a **real device** for actual processing |
| Android | Bundled U2-Net light (default) | API 21+ | Segmentation model ships with the app; no Google Play services model download |
| Android | ML Kit Subject Segmentation (opt-in) | API 24+ | Comparison backend only; uses Google Play services optional module |

> **Important**
>
> - On **iOS Simulator**, foreground extraction is not available. Use a real iPhone or iPad.
> - On **Android**, the U2-Net light model is bundled in the app. The default `removeBackground` path works offline and does not depend on Google Play services optional ML modules.
> - The ML Kit backend is opt-in for quality comparison. Its native crashes cannot be caught by Dart/Kotlin, so do not make it the default for broad production rollout without device gating.

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  native_cutout: ^0.1.0
```

Then run:

```bash
flutter pub get
```

## iOS setup

The plugin compiles against **iOS 13.0+** (Flutter's default), so it will not
raise your app's deployment target. At **runtime** the background-removal API
(`VNGenerateForegroundInstanceMaskRequest`) requires **iOS 17.0+** — on older
versions `removeBackground` returns the error code `UNSUPPORTED_OS`.

No `Podfile` changes are required. Just run pods as usual:

```bash
cd ios && pod install
```

## Android setup

The plugin supports **Android API 21+** and requires no manual `AndroidManifest.xml` changes.

### How the Android model is delivered

The Android model is bundled with the plugin as `u2netp.onnx` (U2-Net light).
There is no ML Kit / Google Play services optional module to download, load, or
evict, so the cutout feature works offline immediately after installation.

`NativeCutout.isModelAvailable()`, `NativeCutout.downloadModel()`,
`NativeCutout.downloadProgress`, and `NativeCutout.clearModel()` are still
available for existing app code. With the default U2-Net backend they complete
immediately because there is no remote model lifecycle to manage. With
`CutoutBackend.mlKitSubject`, they proxy the Google Play services optional
module lifecycle.

## Quick start

### Default flow: return a cached PNG file path

By default, `native_cutout` writes the result PNG to the app cache directory and returns a file path.

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:native_cutout/native_cutout.dart';

final result = await NativeCutout.removeBackground(
  imagePath,
  options: const CutoutOptions(
    backend: CutoutBackend.u2Net,
    cropToSubject: true,
    writeToCache: true,
  ),
);

late final Widget preview;

switch (result) {
  case CutoutFileSuccess(:final path):
    preview = Image.file(File(path));
    break;
  case CutoutBytesSuccess(:final pngBytes):
    preview = Image.memory(pngBytes);
    break;
  case CutoutFailure(:final code, :final message):
    debugPrint('Cutout failed: ${code.name} - $message');
    return;
}
```

### Android comparison flow: opt into ML Kit

For internal testing, you can run the older ML Kit Subject Segmentation backend
with the same output pipeline:

```dart
final ready = await NativeCutout.isModelAvailable(
  backend: CutoutBackend.mlKitSubject,
);

if (!ready) {
  await NativeCutout.downloadModel(backend: CutoutBackend.mlKitSubject);
}

final result = await NativeCutout.removeBackground(
  imagePath,
  options: const CutoutOptions(
    backend: CutoutBackend.mlKitSubject,
    cropToSubject: true,
  ),
);
```

If the ML Kit optional module is not available, or ML Kit throws a recoverable
load/inference error, Android logs a warning and falls back to the bundled
U2-Net backend. Keep this behind an internal tester toggle or device allowlist:
ML Kit still uses a Google Play services optional native module, so fatal native
failures such as `SIGBUS`, `SIGSEGV`, or `SIGABRT` are not recoverable in app
code.

### In-memory flow: return PNG bytes directly

If you explicitly need raw bytes in Dart, disable cache writing:

```dart
final result = await NativeCutout.removeBackground(
  imagePath,
  options: const CutoutOptions(writeToCache: false),
);
```

## Android warm-up compatibility flow

Existing Android setup code can keep checking the model before processing:

```dart
final isReady = await NativeCutout.isModelAvailable();

if (!isReady) {
  final downloaded = await NativeCutout.downloadModel();
  if (!downloaded) {
    debugPrint('Model warm-up failed');
    return;
  }
}

final result = await NativeCutout.removeBackground(imagePath);
```

If you already surface model progress in your UI:

```dart
final sub = NativeCutout.downloadProgress.listen((progress) {
  debugPrint('state=${progress.state} fraction=${progress.fraction}');
});

final ok = await NativeCutout.downloadModel();
await sub.cancel();
```

`downloadModel()` emits a completed event immediately on Android for the default
U2-Net backend because the model is bundled. Pass
`backend: CutoutBackend.mlKitSubject` to request the ML Kit optional module.

If you need to call the old clear-model path:

```dart
await NativeCutout.clearModel();
final isStillAvailable = await NativeCutout.isModelAvailable();
debugPrint('available after clear: $isStillAvailable');
```

`clearModel()` is a no-op for the default U2-Net backend and the model remains
available. Pass `backend: CutoutBackend.mlKitSubject` to ask Play services to
release the ML Kit optional module.

If you are using cached file output, you can also clear old generated PNGs:

```dart
await NativeCutout.clearCache();
```

On iOS and Android with the default U2-Net/Vision paths:

- `isModelAvailable()` always returns `true`
- `downloadModel()` is a no-op and returns `true`
- `clearModel()` is a no-op and returns `true`

## API overview

### `NativeCutout.removeBackground`

Removes the background from a local image file.

```dart
Future<CutoutResult> NativeCutout.removeBackground(
  String imagePath, {
  CutoutOptions? options,
})
```

Parameters:

- `imagePath`: absolute path to a local image file on device storage
- `options`: optional cutout configuration

Returns:

- `CutoutFileSuccess` with a cached PNG file path (default)
- `CutoutBytesSuccess` with PNG bytes when `writeToCache` is `false`
- `CutoutFailure` with `code` and `message`

### `CutoutOptions`

```dart
const CutoutOptions(
  backend: CutoutBackend.u2Net,
  cropToSubject: false,
  writeToCache: true,
)
```

Available fields:

- `cropToSubject`: when `true`, trims transparent margins and returns a tight subject crop; when `false`, preserves the original image canvas size
- `writeToCache`: when `true` (default), writes the PNG to the app cache directory and returns `CutoutFileSuccess`; when `false`, returns `CutoutBytesSuccess`
- `backend`: Android segmentation backend. Defaults to `CutoutBackend.u2Net`; use `CutoutBackend.mlKitSubject` only for controlled comparison testing.
  Recoverable ML Kit availability/load failures fall back to U2-Net.

### `NativeCutout.clearCache`

Deletes PNG files previously written by the plugin into the app cache directory.

```dart
Future<bool> NativeCutout.clearCache()
```

### `NativeCutout.isModelAvailable`

Checks whether the native model/runtime is ready to use.

```dart
Future<bool> NativeCutout.isModelAvailable({
  CutoutBackend backend = CutoutBackend.u2Net,
})
```

### `NativeCutout.downloadModel`

Warms up the Android model path when needed. With the bundled U2-Net model this
returns `true` immediately and emits a completed progress event. With ML Kit,
this requests the Play services optional module.

```dart
Future<bool> NativeCutout.downloadModel({
  CutoutBackend backend = CutoutBackend.u2Net,
})
```

### `NativeCutout.clearModel`

Requests release of platform-managed model resources. With the bundled Android
model this is a no-op and returns `true`. With ML Kit, this requests release of
the optional module.

```dart
Future<bool> NativeCutout.clearModel({
  CutoutBackend backend = CutoutBackend.u2Net,
})
```

### `NativeCutout.downloadProgress`

Broadcast stream of Android model warm-up progress events.

```dart
Stream<ModelDownloadProgress> get NativeCutout.downloadProgress
```

Notes:

- Emits a completed event immediately on Android while the default U2-Net `downloadModel()` is running
- Returns an empty stream on iOS
- Each event includes `state`, `bytesDownloaded`, `totalBytes`, `errorCode`, and computed `fraction`

## Result types

### `CutoutFileSuccess`

Successful result containing a cached PNG path:

```dart
class CutoutFileSuccess extends CutoutSuccess {
  final String path;
}
```

### `CutoutBytesSuccess`

Successful result containing in-memory PNG bytes:

```dart
class CutoutBytesSuccess extends CutoutSuccess {
  final Uint8List pngBytes;
}
```

### `CutoutFailure`

Failed result containing a typed error code and readable message:

```dart
class CutoutFailure extends CutoutResult {
  final CutoutErrorCode code;
  final String message;
}
```

## Error codes

| Error code | Meaning |
| --- | --- |
| `invalidInput` | The image path is missing, invalid, or the file could not be decoded |
| `noSubjectFound` | No clear foreground subject was detected in the image |
| `processingFailed` | Native processing failed for another reason |

## Output behavior

- The output is always a **PNG with transparent background**
- By default, the plugin writes the PNG to the app cache directory and returns a file path
- If `writeToCache` is `false`, the plugin returns PNG bytes in memory
- The background is made transparent
- Transparent borders are trimmed only when `cropToSubject` is set to `true`
- Cached PNGs can be removed with `NativeCutout.clearCache()`

## Best results

For the highest-quality cutout:

- Use images with a **clear foreground subject**
- Prefer images where the subject is visually separated from the background
- Avoid heavily blurred, extremely dark, or very low-resolution inputs

## Limitations

- Input must be a **local file path**
- iOS processing requires **iOS 17+** and a **real device**
- Android bundles the U2-Net light model, so there is no Play services model download and cutout works offline
- The quality of the result depends on the platform segmentation engine and source image quality

## Example app

The [`example/`](example/) app in this repository demonstrates:

- picking an image from the gallery
- checking/warming up the Android model
- observing Android model warm-up progress
- calling the compatibility clear-model path
- running background removal
- toggling `cropToSubject` on the result page
- toggling `writeToCache` to compare cache-file vs memory-bytes output
- previewing before/after results
- comparing cached-file output dimensions with the original image
- saving the transparent PNG output

## License

MIT

The bundled Android `u2netp.onnx` model is a U2-Net light variant derived from
the Apache-2.0 licensed U-2-Net project.
