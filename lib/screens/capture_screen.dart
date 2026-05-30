import 'dart:async';
import 'dart:io' show File;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/detection.dart';
import '../models/seed_scan_mode.dart';
import '../services/corn_variety_classifier.dart';
import '../services/viability_classifier.dart';
import '../utils/camera_image_input.dart';
import '../services/yolo_service.dart';
import '../utils/detection_projection.dart';
import '../utils/inference_constants.dart';
import '../utils/seed_scan_pipeline.dart';
import '../widgets/detection_overlay.dart';

/// Single photo: capture → YOLO → variety or viability classifier.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.cameras,
    this.scanMode = SeedScanMode.variety,
  });

  final List<CameraDescription> cameras;
  final SeedScanMode scanMode;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _controller;
  final YoloService yolo = YoloService();
  final CornVarietyClassifier variety = CornVarietyClassifier();
  final ViabilityClassifier viability = ViabilityClassifier();

  String? _initError;
  bool _busy = false;

  /// After a successful capture: still image + letterbox-space detections (projected in build).
  Uint8List? _resultBytes;
  LetterboxLayout? _resultLayout;
  List<Detection> _resultLetterbox = [];

  int _varietyDisplayNonce = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    if (widget.cameras.isEmpty) {
      if (mounted) {
        setState(() => _initError = 'No camera available.');
      }
      return;
    }
    try {
      await yolo.loadModel();
      if (widget.scanMode == SeedScanMode.variety) {
        await variety.loadModel();
      } else {
        await viability.loadModel();
      }
      if (!mounted) return;
      final camera = CameraController(
        widget.cameras[0],
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      _controller = camera;
      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _initError = 'Could not start camera: $e');
      }
    }
  }

  Future<List<Detection>> _attachSecondary(
    Uint8List bytes,
    List<Detection> results,
    LetterboxLayout layout,
  ) async {
    if (widget.scanMode == SeedScanMode.variety) {
      return variety.attachVarietyLabels(bytes, results, layout);
    }
    return viability.attachViabilityLabels(bytes, results, layout);
  }

  Future<void> _onCapture() async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized || _busy) return;
    if (camera.value.isTakingPicture) return;

    setState(() => _busy = true);
    try {
      final xfile = await camera.takePicture();
      final bytes = await xfile.readAsBytes();
      final path = xfile.path;
      if (path.isNotEmpty) {
        unawaited((() async {
          try {
            await File(path).delete();
          } catch (_) {}
        })());
      }

      final piped = await runSeedScanPipeline(
        jpegBytes: bytes,
        yolo: yolo,
        attachSecondary: _attachSecondary,
      );
      if (piped == null || !mounted) return;
      if (piped.detections.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No seeds detected at or above '
                '${(kMinYoloConfidence * 100).round()}% confidence.',
              ),
            ),
          );
        }
        setState(() {
          _varietyDisplayNonce++;
          _resultBytes = bytes;
          _resultLayout = piped.layout;
          _resultLetterbox = [];
        });
        return;
      }

      setState(() {
        _varietyDisplayNonce++;
        _resultBytes = bytes;
        _resultLayout = piped.layout;
        _resultLetterbox = piped.detections;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Capture or inference failed.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retake() {
    setState(() {
      _resultBytes = null;
      _resultLayout = null;
      _resultLetterbox = [];
    });
  }

  String _captureTitle() => widget.scanMode == SeedScanMode.variety
      ? 'Capture · variety'
      : 'Capture · viability';

  String _hintText() => widget.scanMode == SeedScanMode.variety
      ? 'Frame the seeds, then tap Capture. YOLO + variety classification runs on the still photo.'
      : 'Frame the seeds, then tap Capture. YOLO + viability classification runs on the still photo.';

  Map<String, int> _classCounts(List<Detection> detections) {
    final counts = <String, int>{};
    for (final d in detections) {
      final label = widget.scanMode == SeedScanMode.variety
          ? d.varietyLabel
          : d.viabilityLabel;
      if (label == null || label.isEmpty) continue;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        return a.key.compareTo(b.key);
      });
    return {for (final e in entries) e.key: e.value};
  }

  Widget _captureSummaryCard(List<Detection> detections) {
    final total = detections.length;
    final counts = _classCounts(detections);
    final modeText = widget.scanMode == SeedScanMode.variety
        ? 'Variety Summary'
        : 'Viability Summary';
    final topClass = counts.isEmpty ? '-' : counts.entries.first.key;
    final topClassCount = counts.isEmpty ? 0 : counts.entries.first.value;
    final theme = Theme.of(context);

    String pretty(String raw) {
      final cleaned = raw.replaceAll('-', ' ').replaceAll('_', ' ');
      return cleaned
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
          .join(' ');
    }

    Widget metricTile(String label, String value, {IconData? icon}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    modeText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.scanMode == SeedScanMode.variety ? 'Variety' : 'Viability',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                metricTile(
                  'Total seeds',
                  '$total',
                  icon: Icons.grain_outlined,
                ),
                const SizedBox(width: 10),
                metricTile(
                  'Top class',
                  '${pretty(topClass)} ($topClassCount)',
                  icon: Icons.emoji_events_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (counts.isEmpty)
              Text(
                'No class labels available.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              Text(
                'Class breakdown',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: counts.entries
                    .map(
                      (e) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.45,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Text(
                          '${pretty(e.key)}: ${e.value}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    yolo.dispose();
    variety.dispose();
    viability.dispose();
    final c = _controller;
    _controller = null;
    if (c != null) {
      unawaited(c.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_captureTitle())),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_initError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (_resultBytes != null && _resultLayout != null) {
      final bytes = _resultBytes!;
      return Scaffold(
        appBar: AppBar(
          title: Text(_captureTitle()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Column(
          children: [
            _captureSummaryCard(_resultLetterbox),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final layout = _resultLayout!;
                  final bounds = Size(constraints.maxWidth, constraints.maxHeight);
                  final imageRect = imageRectContain(
                    bounds,
                    layout.srcWidth,
                    layout.srcHeight,
                  );
                  final projected = projectDetectionsToScreen(
                    _resultLetterbox,
                    layout,
                    imageRect,
                  );
                  return Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: imageRect.left,
                        top: imageRect.top,
                        width: imageRect.width,
                        height: imageRect.height,
                        child: Image.memory(bytes, fit: BoxFit.fill),
                      ),
                      DetectionOverlay(
                        detections: projected,
                        varietyDisplayNonce: _varietyDisplayNonce,
                      ),
                    ],
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _retake,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Capture again'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: Text(_captureTitle())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_captureTitle()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(c),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('Running YOLO & classifier…'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _onCapture,
                    icon: const Icon(Icons.camera_alt),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Capture image'),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Card(
                color: Colors.black54,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    _hintText(),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.95)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
