# native_cutout

[![pub package](https://img.shields.io/pub/v/native_cutout.svg)](https://pub.dev/packages/native_cutout)
[![pub points](https://img.shields.io/pub/points/native_cutout)](https://pub.dev/packages/native_cutout/score)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue.svg)](https://pub.dev/packages/native_cutout)

Native background removal for Flutter using platform image segmentation APIs.

`native_cutout` removes the background from a local image file and produces a transparent PNG — fully on-device, with no external API, no upload step, and no API keys.

| Home · model manager | Cutout result |
| :---: | :---: |
| <img src="https://raw.githubusercontent.com/xcc3641/flutter_native_cutout/main/images/1.png" width="320" alt="Home page with Android model manager" /> | <img src="https://raw.githubusercontent.com/xcc3641/flutter_native_cutout/main/images/2.png" width="320" alt="Cutout result with cropToSubject and writeToCache toggles" /> |

It is built on top of:

- **iOS**: Vision Framework (`VNGenerateForegroundInstanceMaskRequest`)
- **Android**: Google ML Kit Subject Segmentation

## Features

- Fully **on-device** background removal
- Default **file-backed output** written to the app cache directory
- Optional **in-memory PNG bytes** output when you need bytes in Dart
- Native image processing on both iOS and Android
- Handles **EXIF orientation** before segmentation
- Optional subject-bound cropping via `CutoutOptions.cropToSubject`
- Cache management via `clearCache()`
- Android model lifecycle helpers: availability check, download, progress, and clear
- Simple Dart API with typed success/failure results

## Platform support

| Platform | Engine | Minimum version | Notes |
| --- | --- | --- | --- |
| iOS | Vision Framework | iOS 17.0 | Requires a **real device** for actual processing |
| Android | ML Kit Subject Segmentation | API 21+ | First use may require model download via Google Play Services |

> **Important**
>
> - On **iOS Simulator**, foreground extraction is not available. Use a real iPhone or iPad.
> - On **Android**, the ML Kit model may not be available on first launch. You can check availability and trigger a download before processing.

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

This plugin relies on APIs that require **iOS 17.0+**.

Update your app's `ios/Podfile`:

```ruby
platform :ios, '17.0'
```

Then install pods as usual:

```bash
cd ios && pod install
```

## Android setup

No manual manifest setup is required for the plugin itself.

The plugin supports **Android API 21+**. On some devices, the ML Kit segmentation module may need to be downloaded before the first successful cutout.

For testing, the plugin also exposes a best-effort `clearModel()` API on Android to request release of the downloaded module.

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

### In-memory flow: return PNG bytes directly

If you explicitly need raw bytes in Dart, disable cache writing:

```dart
final result = await NativeCutout.removeBackground(
  imagePath,
  options: const CutoutOptions(writeToCache: false),
);
```

## Recommended Android warm-up flow

If you want a more reliable first-run experience on Android, check the model before processing:

```dart
final isReady = await NativeCutout.isModelAvailable();

if (!isReady) {
  final downloaded = await NativeCutout.downloadModel();
  if (!downloaded) {
    debugPrint('ML Kit model download failed');
    return;
  }
}

final result = await NativeCutout.removeBackground(imagePath);
```

If you want to surface download progress in your UI:

```dart
final sub = NativeCutout.downloadProgress.listen((progress) {
  debugPrint('state=${progress.state} fraction=${progress.fraction}');
});

final ok = await NativeCutout.downloadModel();
await sub.cancel();
```

If you need to re-test the first-download flow on Android:

```dart
await NativeCutout.clearModel();
final isStillAvailable = await NativeCutout.isModelAvailable();
debugPrint('available after clear: $isStillAvailable');
```

If you are using cached file output, you can also clear old generated PNGs:

```dart
await NativeCutout.clearCache();
```

On iOS:

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
  cropToSubject: false,
  writeToCache: true,
)
```

Available fields:

- `cropToSubject`: when `true`, trims transparent margins and returns a tight subject crop; when `false`, preserves the original image canvas size
- `writeToCache`: when `true` (default), writes the PNG to the app cache directory and returns `CutoutFileSuccess`; when `false`, returns `CutoutBytesSuccess`

### `NativeCutout.clearCache`

Deletes PNG files previously written by the plugin into the app cache directory.

```dart
Future<bool> NativeCutout.clearCache()
```

### `NativeCutout.isModelAvailable`

Checks whether the native model/runtime is ready to use.

```dart
Future<bool> NativeCutout.isModelAvailable()
```

### `NativeCutout.downloadModel`

Triggers download of the Android ML Kit segmentation module when needed.

```dart
Future<bool> NativeCutout.downloadModel()
```

### `NativeCutout.clearModel`

Requests release of the downloaded Android ML Kit module.

```dart
Future<bool> NativeCutout.clearModel()
```

> **Note**
>
> On Android this delegates to Google Play services `releaseModules(...)`, which is a **best-effort** request. The model may not disappear immediately, so call `isModelAvailable()` again to refresh the current state.

### `NativeCutout.downloadProgress`

Broadcast stream of Android model download progress events.

```dart
Stream<ModelDownloadProgress> get NativeCutout.downloadProgress
```

Notes:

- Only emits on Android while `downloadModel()` is running
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
- Android may require an **initial model download**
- The quality of the result depends on the platform segmentation engine and source image quality

## Example app

The [`example/`](example/) app in this repository demonstrates:

- picking an image from the gallery
- checking/downloading the Android model
- observing Android model download progress
- clearing the Android model and refreshing availability for repeat testing
- running background removal
- toggling `cropToSubject` on the result page
- toggling `writeToCache` to compare cache-file vs memory-bytes output
- previewing before/after results
- comparing cached-file output dimensions with the original image
- saving the transparent PNG output

## License

MIT
