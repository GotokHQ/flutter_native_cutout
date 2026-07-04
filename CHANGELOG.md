## 0.2.1 (GotokHQ fork)

* Added `CutoutOptions.featherRadius` and `CutoutOptions.edgeErode` for higher-fidelity matte edges (both default to `0`, preserving previous behavior).
* iOS: refine the Vision matte with Core Image `CIMorphologyMinimum` (erode) and `CIGaussianBlur` (feather) before compositing.
* Android: replaced the per-pixel mask loop with separable erode/feather + bilinear mask upscale + a `PorterDuff.DST_IN` Canvas composite (smoother edges and faster on large images).

## 0.2.0

* Lowered the iOS pod platform from 17.0 to 13.0 so consuming apps no longer need to raise their deployment target. Background removal still requires iOS 17 at runtime and now returns the `UNSUPPORTED_OS` error on older systems.
* Clarified Android ML Kit model delivery in the README: the segmentation model is not bundled and is downloaded by Google Play services on demand. First call to `removeBackground` will implicitly download the model when missing.
* Added Simplified Chinese translation (`README.zh-CN.md`) and a language switcher in the English README.
* Updated pubspec description to surface on-device processing, iOS 17 runtime requirement, and on-demand ML Kit model download.

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
