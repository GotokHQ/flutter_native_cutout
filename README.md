# native_cutout

A Flutter plugin for AI-powered background removal using native platform APIs. No external services or API keys required - all processing happens on-device.

## Features

- On-device AI processing (no network required)
- Automatic transparent pixel trimming
- High-quality edge detection
- EXIF orientation handling

## Platform Support

| Platform | AI Engine | Minimum Version |
|----------|-----------|-----------------|
| iOS      | Vision Framework (`VNGenerateForegroundInstanceMaskRequest`) | iOS 17.0 |
| Android  | ML Kit Subject Segmentation | API 21 |

> **Note**: iOS requires a real device for processing. The Neural Engine is not available on the Simulator.

## Installation

```yaml
dependencies:
  native_cutout: ^0.0.1
```

### iOS Setup

Ensure your `ios/Podfile` has the minimum deployment target:

```ruby
platform :ios, '17.0'
```

### Android Setup

No additional setup required. ML Kit dependencies are included automatically.

## Usage

```dart
import 'package:native_cutout/native_cutout.dart';

// Remove background from an image
final result = await NativeCutout.removeBackground('/path/to/image.jpg');

switch (result) {
  case CutoutSuccess(:final pngBytes):
    // pngBytes contains PNG image with transparent background
    // Transparent edges are automatically trimmed
    Image.memory(pngBytes);
    break;
  case CutoutFailure(:final code, :final message):
    print('Error: $code - $message');
    break;
}
```

## Error Handling

| Error Code | Description |
|------------|-------------|
| `invalidInput` | Image path is invalid or file cannot be loaded |
| `noSubjectFound` | No foreground subject detected in image |
| `processingFailed` | Error during image processing |

## Example

See the [example](example/) directory for a complete sample app with Before/After comparison.

## License

MIT
