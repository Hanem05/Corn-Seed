import 'dart:async';
import 'dart:io' show File;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../l10n/app_i18n.dart';
import '../widgets/scan_status_panel.dart';

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

  String _captureTitle() =>
      '${AppI18n.t(context, 'guide.capture_headline')} · ${AppI18n.t(context, 'mode.${widget.scanMode.name}')}';

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
    final counts = _classCounts(detections);
    final theme = Theme.of(context);
    String t(String key) => AppI18n.t(context, key);
    return Card(
      margin: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('design.results'), style: theme.textTheme.headlineSmall),
          const SizedBox(height: 20),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text('${detections.length}',
                style: theme.textTheme.headlineLarge?.copyWith(fontSize: 48)),
            const SizedBox(width: 16),
            Expanded(
                child:
                    Text(t('design.total'), style: theme.textTheme.bodyLarge)),
            const Icon(Icons.grain_rounded, size: 32),
          ]),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
          if (detections.isEmpty)
            Text(t('design.empty'))
          else ...[
            Text(t('design.breakdown'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (counts.isEmpty) Text(t('design.unclassified')),
            ...counts.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                          child: Text(
                              entry.key
                                  .replaceAll('-', ' ')
                                  .replaceAll('_', ' '),
                              style: theme.textTheme.labelLarge)),
                      const SizedBox(width: 12),
                      Text('${entry.value}',
                          style: theme.textTheme.titleMedium),
                    ]),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                        value: entry.value / detections.length,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(8),
                        backgroundColor: theme.colorScheme.primaryContainer),
                  ]),
                )),
          ],
        ]),
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
        body: ListView(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.45,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final layout = _resultLayout!;
                  final bounds =
                      Size(constraints.maxWidth, constraints.maxHeight);
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
            _captureSummaryCard(_resultLetterbox),
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
                        label: Text(AppI18n.t(context, 'design.retake')),
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
                  FilledButton.icon(
                    onPressed: _busy ? null : _onCapture,
                    icon: const Icon(Icons.camera_alt),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(AppI18n.t(context,
                          _busy ? 'design.analyzing' : 'design.capture')),
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
              child: ScanStatusPanel(
                title: AppI18n.t(
                    context, _busy ? 'design.analyzing' : 'design.ready'),
                message: AppI18n.t(context, 'design.footer'),
                busy: _busy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
