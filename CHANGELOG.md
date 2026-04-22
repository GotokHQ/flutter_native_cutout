## 0.1.0

* Initial release of the native Flutter background-removal plugin.
* iOS implementation powered by Vision Framework `VNGenerateForegroundInstanceMaskRequest` (iOS 17+).
* Android implementation powered by ML Kit Subject Segmentation.
* Added `CutoutOptions.cropToSubject` for optional subject-bound cropping.
* Added `CutoutOptions.writeToCache` with file-backed PNG output enabled by default.
* Added typed result models: `CutoutFileSuccess`, `CutoutBytesSuccess`, and `CutoutFailure`.
* Added cache cleanup via `NativeCutout.clearCache()`.
* Added Android model lifecycle APIs: `isModelAvailable()`, `downloadModel()`, `downloadProgress`, and `clearModel()`.
* Expanded the example app and README to cover model management, output modes, and result comparison.
