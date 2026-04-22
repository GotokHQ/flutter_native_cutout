import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:native_cutout/native_cutout.dart';

import 'cutout_page.dart';

const String _sampleAsset = 'assets/cat.jpg';
const String _modelDocUrl =
    'https://developers.google.com/ml-kit/vision/subject-segmentation';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();

  bool? _isModelAvailable;
  bool _isDownloadingModel = false;
  bool _isClearingModel = false;
  ModelDownloadProgress? _progress;
  StreamSubscription<ModelDownloadProgress>? _progressSub;

  @override
  void initState() {
    super.initState();
    _checkModelAvailability();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  Future<bool> _checkModelAvailability() async {
    final available = await NativeCutout.isModelAvailable();
    if (mounted) setState(() => _isModelAvailable = available);
    return available;
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloadingModel = true;
      _progress = null;
    });

    _progressSub = NativeCutout.downloadProgress.listen((p) {
      if (mounted) setState(() => _progress = p);
    });

    final success = await NativeCutout.downloadModel();

    await _progressSub?.cancel();
    _progressSub = null;

    if (!mounted) return;
    setState(() {
      _isDownloadingModel = false;
      _isModelAvailable = success;
      _progress = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Model downloaded successfully'
              : 'Failed to download model',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _clearModel() async {
    await _progressSub?.cancel();
    _progressSub = null;

    setState(() {
      _isClearingModel = true;
      _isDownloadingModel = false;
      _progress = null;
    });

    final requested = await NativeCutout.clearModel();
    final stillAvailable = await _checkModelAvailability();

    if (!mounted) return;
    setState(() => _isClearingModel = false);

    final (message, color) = switch ((requested, stillAvailable)) {
      (false, _) => ('Failed to request model release', Colors.red),
      (true, false) => (
        'Model cleared. You can test the download flow again.',
        Colors.green,
      ),
      (true, true) => (
        'Release requested. Google Play Services may keep the model for a while.',
        Colors.orange,
      ),
    };

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _pickFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    _openCutoutPage(image.path);
  }

  Future<void> _trySample() async {
    final data = await rootBundle.load(_sampleAsset);
    final file = File('${Directory.systemTemp.path}/sample_cat.jpg');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    if (!mounted) return;
    _openCutoutPage(file.path);
  }

  void _openCutoutPage(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CutoutPage(imagePath: path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canRun = _isModelAvailable == true;
    final isAndroid = Platform.isAndroid;
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
            if (isAndroid) ...[
              _ModelManagerCard(
                isModelAvailable: _isModelAvailable,
                isDownloading: _isDownloadingModel,
                isClearing: _isClearingModel,
                progress: _progress,
                onDownload: _downloadModel,
                onClear: _clearModel,
                onRefresh: _checkModelAvailability,
              ),
              const SizedBox(height: 16),
            ],
            if (_isModelAvailable == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              ElevatedButton.icon(
                onPressed: canRun ? _pickFromGallery : null,
                icon: const Icon(Icons.photo_library),
                label: const Text('Pick from Gallery'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: canRun ? _trySample : null,
                icon: const Icon(Icons.pets),
                label: const Text('Try Sample Image'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelManagerCard extends StatelessWidget {
  const _ModelManagerCard({
    required this.isModelAvailable,
    required this.isDownloading,
    required this.isClearing,
    required this.progress,
    required this.onDownload,
    required this.onClear,
    required this.onRefresh,
  });

  final bool? isModelAvailable;
  final bool isDownloading;
  final bool isClearing;
  final ModelDownloadProgress? progress;
  final VoidCallback onDownload;
  final VoidCallback onClear;
  final Future<bool> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              isDownloading
                  ? Icons.cloud_download
                  : isClearing
                  ? Icons.delete_outline
                  : isModelAvailable == true
                  ? Icons.verified
                  : Icons.download,
              size: 48,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(height: 8),
            Text(
              isDownloading
                  ? 'Downloading model...'
                  : isClearing
                  ? 'Releasing model...'
                  : 'Android model manager',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _StatusChip(isModelAvailable: isModelAvailable, scheme: scheme),
            const SizedBox(height: 12),
            if (isDownloading)
              _ProgressDetails(progress: progress, scheme: scheme)
            else
              _IntroDetails(scheme: scheme, isModelAvailable: isModelAvailable),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        (isDownloading ||
                            isClearing ||
                            isModelAvailable == true)
                        ? null
                        : onDownload,
                    icon: isDownloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(isDownloading ? 'Downloading' : 'Download model'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        (isDownloading ||
                            isClearing ||
                            isModelAvailable != true)
                        ? null
                        : onClear,
                    icon: isClearing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(isClearing ? 'Releasing' : 'Release model'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: (isDownloading || isClearing)
                    ? null
                    : () async {
                        final available = await onRefresh();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              available
                                  ? 'Model is currently available'
                                  : 'Model is currently unavailable',
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh status'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroDetails extends StatelessWidget {
  const _IntroDetails({required this.scheme, required this.isModelAvailable});

  final ColorScheme scheme;
  final bool? isModelAvailable;

  @override
  Widget build(BuildContext context) {
    final textColor = scheme.onTertiaryContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoRow(label: 'Source', value: 'Google Play Services', color: textColor),
        _InfoRow(
          label: 'Model',
          value: 'ML Kit Subject Segmentation',
          color: textColor,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onLongPress: () async {
            await Clipboard.setData(const ClipboardData(text: _modelDocUrl));
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Documentation link copied')));
          },
          child: Text(
            _modelDocUrl,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              decoration: TextDecoration.underline,
              decorationColor: textColor.withValues(alpha: 0.5),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isModelAvailable == true
              ? 'Model is available. Tap "Release model" to test the first-download flow again. Long-press the link above to copy it.'
              : 'On first use the model is downloaded from Google Play Services and cached locally. Long-press the link above to copy it.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isModelAvailable == true
              ? '⚠️ Releasing is a best-effort request; Google Play Services may keep the model for a while.'
              : '💡 Requires an internet connection',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isModelAvailable, required this.scheme});

  final bool? isModelAvailable;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (isModelAvailable) {
      true => ('Installed', Colors.green),
      false => ('Not installed', scheme.error),
      null => ('Checking', scheme.onTertiaryContainer),
    };
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          'Status: $label',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ProgressDetails extends StatelessWidget {
  const _ProgressDetails({required this.progress, required this.scheme});

  final ModelDownloadProgress? progress;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final fraction = p?.fraction;
    final textColor = scheme.onTertiaryContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: fraction),
        const SizedBox(height: 8),
        Text(
          _statusLine(p),
          textAlign: TextAlign.center,
          style: TextStyle(color: textColor, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          '⚠️ Keep the network connected and stay in the app',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.error,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _statusLine(ModelDownloadProgress? p) {
    if (p == null) return 'Initializing...';
    final stateLabel = switch (p.state) {
      ModelInstallState.pending => 'Pending',
      ModelInstallState.downloading => 'Downloading',
      ModelInstallState.downloadPaused => 'Paused',
      ModelInstallState.installing => 'Installing',
      ModelInstallState.completed => 'Completed',
      ModelInstallState.canceled => 'Canceled',
      ModelInstallState.failed => 'Failed (code: ${p.errorCode})',
      ModelInstallState.unknown => 'Processing',
    };
    if (p.totalBytes <= 0) return stateLabel;
    final current = _formatBytes(p.bytesDownloaded);
    final total = _formatBytes(p.totalBytes);
    final pct = ((p.fraction ?? 0) * 100).toStringAsFixed(0);
    return '$stateLabel · $current / $total ($pct%)';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
