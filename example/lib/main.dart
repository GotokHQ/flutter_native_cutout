import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:native_cutout/native_cutout.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Cutout Demo',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: const CutoutDemoPage(),
    );
  }
}

class CutoutDemoPage extends StatefulWidget {
  const CutoutDemoPage({super.key});

  @override
  State<CutoutDemoPage> createState() => _CutoutDemoPageState();
}

class _CutoutDemoPageState extends State<CutoutDemoPage> {
  final ImagePicker _picker = ImagePicker();

  String? _originalImagePath;
  Uint8List? _cutoutImageBytes;
  bool _isProcessing = false;
  String? _errorMessage;

  // Debug info
  int? _originalFileSize;
  Size? _originalDimensions;
  Size? _resultDimensions;
  Duration? _processingTime;
  bool _isSaving = false;

  // Model availability (Android only)
  bool? _isModelAvailable;
  bool _isDownloadingModel = false;

  @override
  void initState() {
    super.initState();
    _checkModelAvailability();
  }

  Future<void> _checkModelAvailability() async {
    final available = await NativeCutout.isModelAvailable();
    if (mounted) {
      setState(() => _isModelAvailable = available);
    }
  }

  Future<void> _downloadModel() async {
    setState(() => _isDownloadingModel = true);

    final success = await NativeCutout.downloadModel();

    if (mounted) {
      setState(() {
        _isDownloadingModel = false;
        _isModelAvailable = success;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Model downloaded successfully' : 'Failed to download model'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _pickAndProcess() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    // Get original file info
    final file = File(image.path);
    final fileSize = await file.length();

    setState(() {
      _originalImagePath = image.path;
      _originalFileSize = fileSize;
      _cutoutImageBytes = null;
      _errorMessage = null;
      _isProcessing = true;
      _originalDimensions = null;
      _resultDimensions = null;
      _processingTime = null;
    });

    // Get original image dimensions
    final originalBytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(originalBytes);
    final frame = await codec.getNextFrame();
    final originalSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();

    setState(() {
      _originalDimensions = originalSize;
    });

    // Process image
    final stopwatch = Stopwatch()..start();
    final result = await NativeCutout.removeBackground(image.path);
    stopwatch.stop();

    setState(() {
      _isProcessing = false;
      _processingTime = stopwatch.elapsed;

      switch (result) {
        case CutoutSuccess(:final pngBytes):
          _cutoutImageBytes = pngBytes;
          _errorMessage = null;
          _loadResultDimensions(pngBytes);
        case CutoutFailure(:final code, :final message):
          _cutoutImageBytes = null;
          _errorMessage = '${code.name}: $message';
      }
    });
  }

  Future<void> _loadResultDimensions(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _resultDimensions = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    });
    frame.image.dispose();
  }

  Future<void> _saveToGallery() async {
    if (_cutoutImageBytes == null) return;

    setState(() => _isSaving = true);

    try {
      await Gal.putImageBytes(_cutoutImageBytes!, name: 'cutout_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved to gallery'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Native Cutout Demo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Model download banner for Android
            if (_isModelAvailable == false) ...[
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        _isDownloadingModel ? Icons.cloud_download : Icons.download,
                        size: 48,
                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isDownloadingModel ? '正在下载模型...' : 'ML 模型需要下载',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_isDownloadingModel) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          '正在从 Google Play Services 下载 Subject Segmentation 模型\n'
                          '这可能需要 30 秒到几分钟，取决于网络速度',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '⚠️ 请保持网络连接，勿退出应用',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ] else ...[
                        Text(
                          '首次使用需要下载 Google ML Kit 的图像分割模型\n'
                          '模型大小约 10-20MB，下载后会缓存在设备中',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '💡 需要连接互联网',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onTertiaryContainer.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isDownloadingModel ? null : _downloadModel,
                          icon: _isDownloadingModel
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download),
                          label: Text(_isDownloadingModel ? '下载中，请稍候...' : '立即下载模型'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_isModelAvailable == null)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton.icon(
                onPressed: (_isProcessing || _isModelAvailable == false) ? null : _pickAndProcess,
                icon: const Icon(Icons.image),
                label: const Text('Select Image'),
              ),
            const SizedBox(height: 24),

            if (_isProcessing)
              const Center(
                child: Column(children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Processing...')]),
              ),
            if (_errorMessage != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                ),
              ),
            // Before / After comparison
            if (_originalImagePath != null && _cutoutImageBytes != null && !_isProcessing) ...[
              // Processing time and save button
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_processingTime != null)
                      Text(
                        'Processing time: ${_processingTime!.inMilliseconds} ms',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.green),
                      ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveToGallery,
                      icon: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_alt),
                      label: Text(_isSaving ? 'Saving...' : 'Save'),
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Before
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Before', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(_originalImagePath!), height: 250, fit: BoxFit.contain),
                        ),
                        const SizedBox(height: 8),
                        _buildInfoCard('Original', [
                          if (_originalDimensions != null)
                            '${_originalDimensions!.width.toInt()} × ${_originalDimensions!.height.toInt()}',
                          if (_originalFileSize != null) _formatFileSize(_originalFileSize!),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // After - use same aspect ratio as original
                  Expanded(
                    child: Column(
                      children: [
                        const Text('After', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        // Container with same height as Before, centered result,
                        SizedBox(height: 250, child: Image.memory(_cutoutImageBytes!, fit: BoxFit.contain)),
                        const SizedBox(height: 8),
                        _buildInfoCard('Result', [
                          if (_resultDimensions != null)
                            '${_resultDimensions!.width.toInt()} × ${_resultDimensions!.height.toInt()}',
                          _formatFileSize(_cutoutImageBytes!.length),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ] else if (_originalImagePath != null && !_isProcessing) ...[
              // Show only original when no result yet
              const Text('Original', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(_originalImagePath!), height: 300, fit: BoxFit.contain),
              ),
              const SizedBox(height: 8),
              if (_originalDimensions != null && _originalFileSize != null)
                _buildInfoCard('Original', [
                  '${_originalDimensions!.width.toInt()} × ${_originalDimensions!.height.toInt()}',
                  _formatFileSize(_originalFileSize!),
                ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, List<String> info) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ...info.map((text) => Text(text, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}
