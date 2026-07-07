# native_cutout

[![pub package](https://img.shields.io/pub/v/native_cutout.svg)](https://pub.dev/packages/native_cutout)
[![pub points](https://img.shields.io/pub/points/native_cutout)](https://pub.dev/packages/native_cutout/score)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue.svg)](https://pub.dev/packages/native_cutout)

[English](README.md) | 简体中文

基于系统原生图像分割能力的 Flutter 抠图插件。

`native_cutout` 读取本地图片文件、去除背景、生成透明 PNG —— 全程**端侧处理**，不调用任何后端 API、不上传图片、不需要 API Key。

| 主页 · 模型管理 | 抠图结果 |
| :---: | :---: |
| <img src="https://raw.githubusercontent.com/xcc3641/flutter_native_cutout/main/images/1.png" width="320" alt="带 Android 模型管理的主页" /> | <img src="https://raw.githubusercontent.com/xcc3641/flutter_native_cutout/main/images/2.png" width="320" alt="带 cropToSubject 与 writeToCache 开关的抠图结果" /> |

底层依赖：

- **iOS**：Vision Framework（`VNGenerateForegroundInstanceMaskRequest`）
- **Android**：随包内置的 U2-Net light 模型，通过 Android 原生推理运行时执行

## 功能特性

- 完全**端侧**完成背景去除
- 默认**写入缓存目录**并返回文件路径
- 可选**内存 PNG 字节**输出，便于直接在 Dart 层使用
- iOS / Android 两端原生图像处理
- 分割前自动修正 **EXIF 方向**
- 可选「贴合主体」裁剪 `CutoutOptions.cropToSubject`
- `clearCache()` 清理缓存
- Android 保留模型生命周期 API 以兼容旧代码（模型随包内置，无需网络下载）
- 简洁的 Dart API，结果类型严格区分成功 / 失败

## 平台支持

| 平台 | 引擎 | 最低版本 | 备注 |
| --- | --- | --- | --- |
| iOS | Vision Framework | iOS 13.0（编译）/ iOS 17.0（运行时） | 实际抠图需要**真机** |
| Android | 内置 U2-Net light | API 21+ | 分割模型随 App 打包，无需 Google Play Services 下载 |

> **重要提示**
>
> - **iOS 模拟器**不支持前景分割，请使用 iPhone / iPad 真机。
> - **Android 端的 U2-Net light 模型会随 App 一起打包**。`removeBackground` 可离线工作，不依赖 Google Play services 的可选 ML 模块。

## 安装

`pubspec.yaml`：

```yaml
dependencies:
  native_cutout: ^0.1.0
```

然后执行：

```bash
flutter pub get
```

## iOS 接入

插件**编译目标**为 **iOS 13.0+**（与 Flutter 默认一致），**不会**抬高你 App 的最低部署版本。

**运行时**的背景去除 API（`VNGenerateForegroundInstanceMaskRequest`）需要 **iOS 17.0+**；在更低版本系统上调用 `removeBackground` 会返回错误码 `UNSUPPORTED_OS`。

无需修改 `Podfile`，正常安装即可：

```bash
cd ios && pod install
```

## Android 接入

插件支持 **Android API 21+**，**不需要**手动改 `AndroidManifest.xml`。

### Android 模型如何下发

Android 模型以 `u2netp.onnx`（U2-Net light）的形式随插件打包。这里不再使用
ML Kit / Google Play services 的可选模块，因此没有远程模型下载、加载或被系统清理的问题；
安装后即可离线使用抠图能力。

`NativeCutout.isModelAvailable()`、`NativeCutout.downloadModel()`、
`NativeCutout.downloadProgress` 和 `NativeCutout.clearModel()` 仍然保留，
便于兼容已有 App 代码；由于没有远程模型生命周期，它们都会立即完成。

## 快速开始

### 默认流程：返回缓存目录中的 PNG 文件路径

默认情况下 `native_cutout` 会把结果 PNG 写到 App 的缓存目录，并把文件路径返回。

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
    debugPrint('抠图失败: ${code.name} - $message');
    return;
}
```

### 内存字节流程：直接返回 PNG 字节

如果你明确需要在 Dart 层拿到原始字节，关闭缓存写入即可：

```dart
final result = await NativeCutout.removeBackground(
  imagePath,
  options: const CutoutOptions(writeToCache: false),
);
```

## Android 模型预热兼容流程

已有 Android 代码可以继续在处理前检查模型：

```dart
final isReady = await NativeCutout.isModelAvailable();

if (!isReady) {
  final downloaded = await NativeCutout.downloadModel();
  if (!downloaded) {
    debugPrint('模型预热失败');
    return;
  }
}

final result = await NativeCutout.removeBackground(imagePath);
```

如果已有 UI 展示模型进度：

```dart
final sub = NativeCutout.downloadProgress.listen((progress) {
  debugPrint('state=${progress.state} fraction=${progress.fraction}');
});

final ok = await NativeCutout.downloadModel();
await sub.cancel();
```

Android 上 `downloadModel()` 会立即发送一个 completed 事件，因为模型已经随包内置。

如果仍需调用旧的清理模型路径：

```dart
await NativeCutout.clearModel();
final isStillAvailable = await NativeCutout.isModelAvailable();
debugPrint('清除后是否仍可用: $isStillAvailable');
```

Android 上 `clearModel()` 是空操作，模型仍然可用。

使用文件缓存输出时，也可以清除历史生成的 PNG：

```dart
await NativeCutout.clearCache();
```

iOS 和 Android 上：

- `isModelAvailable()` 始终返回 `true`
- `downloadModel()` 是空操作，返回 `true`
- `clearModel()` 是空操作，返回 `true`

## API 总览

### `NativeCutout.removeBackground`

去除本地图片文件的背景。

```dart
Future<CutoutResult> NativeCutout.removeBackground(
  String imagePath, {
  CutoutOptions? options,
})
```

参数：

- `imagePath`：设备本地图片文件的绝对路径
- `options`：可选的抠图配置

返回：

- `CutoutFileSuccess`：缓存 PNG 文件路径（默认）
- `CutoutBytesSuccess`：PNG 字节（`writeToCache` 为 `false` 时）
- `CutoutFailure`：包含 `code` 与 `message`

### `CutoutOptions`

```dart
const CutoutOptions(
  cropToSubject: false,
  writeToCache: true,
)
```

可用字段：

- `cropToSubject`：为 `true` 时裁掉透明边、返回贴合主体的紧凑图；为 `false` 时保留原图画布尺寸
- `writeToCache`：为 `true`（默认）时将 PNG 写入 App 缓存目录并返回 `CutoutFileSuccess`；为 `false` 时返回 `CutoutBytesSuccess`

### `NativeCutout.clearCache`

删除插件之前写入 App 缓存目录的 PNG 文件。

```dart
Future<bool> NativeCutout.clearCache()
```

### `NativeCutout.isModelAvailable`

查询底层原生模型 / 运行时是否就绪。

```dart
Future<bool> NativeCutout.isModelAvailable()
```

### `NativeCutout.downloadModel`

在需要时预热 Android 模型路径。由于 U2-Net 模型随包内置，该方法会立即返回
`true` 并发送 completed 进度事件。

```dart
Future<bool> NativeCutout.downloadModel()
```

### `NativeCutout.clearModel`

请求释放平台管理的模型资源。Android 模型随包内置，因此这是空操作并返回 `true`。

```dart
Future<bool> NativeCutout.clearModel()
```

### `NativeCutout.downloadProgress`

Android 模型预热进度的广播流。

```dart
Stream<ModelDownloadProgress> get NativeCutout.downloadProgress
```

说明：

- Android 上 `downloadModel()` 运行时会立即发出 completed 事件
- iOS 上返回空流
- 每个事件包含 `state`、`bytesDownloaded`、`totalBytes`、`errorCode`，以及计算字段 `fraction`

## 结果类型

### `CutoutFileSuccess`

带缓存 PNG 路径的成功结果：

```dart
class CutoutFileSuccess extends CutoutSuccess {
  final String path;
}
```

### `CutoutBytesSuccess`

带内存 PNG 字节的成功结果：

```dart
class CutoutBytesSuccess extends CutoutSuccess {
  final Uint8List pngBytes;
}
```

### `CutoutFailure`

带类型化错误码与可读消息的失败结果：

```dart
class CutoutFailure extends CutoutResult {
  final CutoutErrorCode code;
  final String message;
}
```

## 错误码

| 错误码 | 含义 |
| --- | --- |
| `invalidInput` | 图片路径缺失、非法，或文件无法解码 |
| `noSubjectFound` | 图中未识别出明确的前景主体 |
| `processingFailed` | 原生处理因其他原因失败 |

## 输出行为

- 输出始终是**带透明背景的 PNG**
- 默认会写入 App 缓存目录并返回文件路径
- 当 `writeToCache` 为 `false` 时，返回内存中的 PNG 字节
- 背景区域会被设为透明
- 仅当 `cropToSubject` 为 `true` 时才会裁掉透明边
- 可通过 `NativeCutout.clearCache()` 清理已缓存的 PNG

## 怎样得到更好的效果

为了获得更高质量的抠图：

- 使用**主体清晰**的图片
- 主体应与背景有明显的视觉区分
- 避免严重模糊、过暗或分辨率极低的输入

## 已知限制

- 输入必须是**本地文件路径**
- iOS 端需要 **iOS 17+** 且**真机**
- Android 端内置 U2-Net light 模型，无需 Play services 模型下载，可离线抠图
- 抠图质量取决于平台分割引擎和源图质量

## Example 示例工程

仓库中的 [`example/`](example/) 工程演示了：

- 从相册选图
- 检查 / 预热 Android 模型
- 监听 Android 模型预热进度
- 调用兼容的清理模型路径
- 执行背景去除
- 在结果页切换 `cropToSubject`
- 切换 `writeToCache`，对比缓存文件输出与内存字节输出
- 预览前后对比
- 比较缓存文件输出尺寸与原图
- 保存生成的透明 PNG

## License

MIT

Android 内置的 `u2netp.onnx` 模型是 U2-Net light 变体，来源于 Apache-2.0
授权的 U-2-Net 项目。
