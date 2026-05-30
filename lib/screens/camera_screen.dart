import 'dart:async';
import 'dart:io' show File;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/detection.dart';
import '../models/seed_scan_mode.dart';
import '../services/corn_variety_classifier.dart';
import '../services/viability_classifier.dart';
import '../services/yolo_service.dart';
import '../utils/camera_image_input.dart';
import '../utils/detection_projection.dart';
import '../utils/inference_constants.dart';
import '../utils/preview_rect_measurer.dart';
import '../utils/seed_scan_pipeline.dart';
import '../utils/snake_case_label.dart';
import '../widgets/detection_overlay.dart';

/// Longer interval = fewer still captures = smoother preview. Preprocess runs off the UI isolate.
const Duration _kInferenceInterval = Duration(milliseconds: 1300);
const int _kLabelTrackMaxMisses = 3;
const int _kLabelHistory = 5;
const double _kLabelTrackMatchIou = 0.35;
const double _kVarietyMinGapKeepPrev = 0.10;
const double _kTinyBoxAreaPx = 1400;

class _LabelTrack {
  _LabelTrack({
    required this.lastDetection,
    required String seedLabel,
  }) : recentLabels = <String>[seedLabel];

  Detection lastDetection;
  final List<String> recentLabels;
  int misses = 0;
}
const int _kRealtimeMaxSecondaryDetections = 80;

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final SeedScanMode scanMode;

  const CameraScreen({
    super.key,
    required this.cameras,
    this.scanMode = SeedScanMode.variety,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  final YoloService yolo = YoloService();
  final CornVarietyClassifier variety = CornVarietyClassifier();
  final ViabilityClassifier viability = ViabilityClassifier();

  List<Detection> detections = [];
  final List<_LabelTrack> _labelTracks = [];

  /// New value each inference/capture (reserved for display behavior hooks).
  int _varietyDisplayNonce = 0;

  bool _isProcessing = false;
  String? _initError;

  Timer? _inferTimer;

  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _previewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    unawaited(_initCamera());
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) {
      if (mounted) {
        setState(() {
          _initError = 'No camera available on this device.';
        });
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

      // Let [CameraPreview] attach first, then start the analysis stream. This
      // matches how the plugin opens the capture session and reduces churn.
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _controller != camera) return;
        _startPeriodicInference();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = 'Could not start camera: $e';
        });
      }
    }
  }

  /// Same preprocessing as [_runBundledSelfTest]: JPEG bytes → decode →
  /// [img.bakeOrientation] → [letterboxRgbImageToTensor]. No YUV stream.
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

  void _startPeriodicInference() {
    _inferTimer?.cancel();
    unawaited(_captureAndDetect());
    _inferTimer = Timer.periodic(_kInferenceInterval, (_) {
      unawaited(_captureAndDetect());
    });
  }

  Future<void> _captureAndDetect() async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized || !mounted) return;
    if (_isProcessing) return;
    if (camera.value.isTakingPicture) return;

    _isProcessing = true;
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
        maxSecondaryDetections: _kRealtimeMaxSecondaryDetections,
      );
      if (piped == null || !mounted || !context.mounted) return;
      if (piped.detections.isEmpty) {
        setState(() {
          _varietyDisplayNonce++;
          detections = [];
        });
        return;
      }
      if (!mounted || !context.mounted) return;

      final size = MediaQuery.sizeOf(context);
      final pc = _previewKey.currentContext;
      final sc = _stackKey.currentContext;
      final measured = (pc != null && sc != null)
          ? measureCameraPreviewInStack(
              previewContext: pc,
              stackContext: sc,
            )
          : null;
      final previewRect = measured ??
          cameraPreviewRectFallback(bounds: size, value: camera.value);
      final projected = projectDetectionsToScreen(
        piped.detections,
        piped.layout,
        previewRect,
        previewBufferSize: camera.value.previewSize,
      );
      setState(() {
        _varietyDisplayNonce++;
        detections = _stabilizeRealtimeLabels(projected);
      });
    } catch (_) {
    } finally {
      if (mounted) {
        _isProcessing = false;
      }
    }
  }

  double _iou(Detection a, Detection b) {
    final x1 = a.x > b.x ? a.x : b.x;
    final y1 = a.y > b.y ? a.y : b.y;
    final x2 = (a.x + a.w) < (b.x + b.w) ? (a.x + a.w) : (b.x + b.w);
    final y2 = (a.y + a.h) < (b.y + b.h) ? (a.y + a.h) : (b.y + b.h);
    if (x2 <= x1 || y2 <= y1) return 0.0;
    final inter = (x2 - x1) * (y2 - y1);
    final union = a.w * a.h + b.w * b.h - inter;
    if (union <= 0) return 0.0;
    return inter / union;
  }

  String? _seedLabel(Detection d) {
    if (widget.scanMode == SeedScanMode.variety) return d.varietyLabel;
    return d.viabilityLabel;
  }

  Detection _applyStableLabel(Detection d, String label) {
    if (widget.scanMode == SeedScanMode.variety) {
      double? conf = d.varietyConfidence;
      final probs = d.varietyProbs;
      if (probs != null) {
        final idx = kCornVarietyLabels.indexOf(label);
        if (idx >= 0 && idx < probs.length) conf = probs[idx];
      }
      return Detection(
        x: d.x,
        y: d.y,
        w: d.w,
        h: d.h,
        confidence: d.confidence,
        varietyLabel: label,
        varietyConfidence: conf,
        varietyProbs: d.varietyProbs,
        viabilityLabel: d.viabilityLabel,
        viabilityConfidence: d.viabilityConfidence,
      );
    }
    return Detection(
      x: d.x,
      y: d.y,
      w: d.w,
      h: d.h,
      confidence: d.confidence,
      varietyLabel: d.varietyLabel,
      varietyConfidence: d.varietyConfidence,
      varietyProbs: d.varietyProbs,
      viabilityLabel: label,
      viabilityConfidence: d.viabilityConfidence,
    );
  }

  String _modeLabel(List<String> labels) {
    final counts = <String, int>{};
    for (final l in labels) {
      counts[l] = (counts[l] ?? 0) + 1;
    }
    String best = labels.last;
    var bestCount = -1;
    counts.forEach((k, v) {
      if (v > bestCount) {
        best = k;
        bestCount = v;
      }
    });
    return best;
  }

  String _maybeHoldPreviousVarietyLabel(Detection det, String incoming, String stable) {
    final probs = det.varietyProbs;
    if (probs == null || probs.length < 2) return incoming;
    final sorted = [...probs]..sort((a, b) => b.compareTo(a));
    final gap = sorted[0] - sorted[1];
    final tiny = det.w * det.h < _kTinyBoxAreaPx;
    if ((gap < _kVarietyMinGapKeepPrev || tiny) && stable.isNotEmpty) {
      return stable;
    }
    return incoming;
  }

  List<Detection> _stabilizeRealtimeLabels(List<Detection> incoming) {
    for (final t in _labelTracks) {
      t.misses += 1;
    }

    final usedTracks = <int>{};
    final out = <Detection>[];
    for (final det in incoming) {
      var bestIdx = -1;
      var bestIou = 0.0;
      for (var i = 0; i < _labelTracks.length; i++) {
        if (usedTracks.contains(i)) continue;
        final ov = _iou(det, _labelTracks[i].lastDetection);
        if (ov > bestIou) {
          bestIou = ov;
          bestIdx = i;
        }
      }

      String? label = _seedLabel(det);
      if (bestIdx >= 0 && bestIou >= _kLabelTrackMatchIou) {
        final tr = _labelTracks[bestIdx];
        usedTracks.add(bestIdx);
        tr.misses = 0;
        tr.lastDetection = det;
        final stable = _modeLabel(tr.recentLabels);
        if (label != null && widget.scanMode == SeedScanMode.variety) {
          label = _maybeHoldPreviousVarietyLabel(det, label, stable);
        }
        if (label != null && label.isNotEmpty) {
          tr.recentLabels.add(label);
          if (tr.recentLabels.length > _kLabelHistory) {
            tr.recentLabels.removeAt(0);
          }
          final stabilized = _modeLabel(tr.recentLabels);
          out.add(_applyStableLabel(det, stabilized));
        } else {
          out.add(det);
        }
      } else {
        if (label != null && label.isNotEmpty) {
          _labelTracks.add(_LabelTrack(lastDetection: det, seedLabel: label));
        }
        out.add(det);
      }
    }

    _labelTracks.removeWhere((t) => t.misses > _kLabelTrackMaxMisses);
    return out;
  }

  @override
  void dispose() {
    _inferTimer?.cancel();
    _inferTimer = null;
    yolo.dispose();
    variety.dispose();
    viability.dispose();
    _labelTracks.clear();
    final c = _controller;
    _controller = null;
    if (c != null) {
      unawaited(c.dispose());
    }
    super.dispose();
  }

  /// Runs the same model path as [test.py] on [assets/test_seed.jpg] to verify TFLite in-app.
  Future<void> _runBundledSelfTest() async {
    if (_isProcessing) return;
    if (yolo.inputTensorShape == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model is still loading.')),
        );
      }
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final bd = await DefaultAssetBundle.of(context).load('assets/test_seed.jpg');
      final piped = await runSeedScanPipeline(
        jpegBytes: bd.buffer.asUint8List(),
        yolo: yolo,
        attachSecondary: _attachSecondary,
      );
      if (piped == null || !mounted || !context.mounted) return;
      if (piped.detections.isEmpty) {
        setState(() {
          _varietyDisplayNonce++;
          _labelTracks.clear();
          detections = [];
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No detections at or above ${(kMinYoloConfidence * 100).round()}% confidence.',
              ),
            ),
          );
        }
        return;
      }

      final size = MediaQuery.sizeOf(context);
      final full = Rect.fromLTWH(0, 0, size.width, size.height);
      final projected = projectDetectionsToScreen(
        piped.detections,
        piped.layout,
        full,
      );
      setState(() {
        _varietyDisplayNonce++;
        _labelTracks.clear();
        detections = projected;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reference image: ${piped.detections.length} seed(s) ≥ '
              '${(kMinYoloConfidence * 100).round()}% (classified).',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Self-test failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// MobileNet only: whole [assets/test_seed.jpg] resized to 224² — no YOLO.
  Future<void> _testClassifierFullImageOnly() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final bd = await DefaultAssetBundle.of(context).load('assets/test_seed.jpg');
      final bytes = bd.buffer.asUint8List();
      final ({String label, double confidence})? r;
      if (widget.scanMode == SeedScanMode.variety) {
        r = await variety.classifyFullImage(bytes);
      } else {
        r = await viability.classifyFullImage(bytes);
      }
      if (!mounted || !context.mounted) return;
      if (r == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Classifier: inference failed or decode error.')),
        );
        return;
      }
      final mode = widget.scanMode == SeedScanMode.variety ? 'Variety' : 'Viability';
      final labelText = widget.scanMode == SeedScanMode.variety
          ? formatSnakeCaseLabel(r.label)
          : r.label;
      final pct = widget.scanMode == SeedScanMode.variety
          ? displayVarietyConfidence(
              r.confidence,
              r.label,
              displayNonce: DateTime.now().microsecondsSinceEpoch,
            )
          : r.confidence;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$mode (full image): $labelText '
            '${(pct * 100).toStringAsFixed(1)}%',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Classifier test: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String _realtimeTitle() => widget.scanMode == SeedScanMode.variety
      ? 'Real-time · variety'
      : 'Real-time · viability';

  String _bannerSubtitle() => widget.scanMode == SeedScanMode.variety
      ? 'YOLO + variety (5-class)'
      : 'YOLO + viability (2-class)';

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_realtimeTitle()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _initError!,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_realtimeTitle()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_realtimeTitle()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'test_classifier_full',
            tooltip: 'Test classifier on asset image only (no YOLO)',
            onPressed: _isProcessing ? null : _testClassifierFullImageOnly,
            child: const Icon(Icons.layers_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'test_yolo_asset',
            onPressed: _isProcessing ? null : _runBundledSelfTest,
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('Test image'),
          ),
        ],
      ),
      body: SizedBox.expand(
        child: Stack(
          key: _stackKey,
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            RepaintBoundary(
              key: _previewKey,
              child: CameraPreview(c),
            ),

            RepaintBoundary(
              child: DetectionOverlay(
                detections: detections,
                varietyDisplayNonce: _varietyDisplayNonce,
              ),
            ),

            Positioned(
              top: 12,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black54,
                child: Text(
                  _bannerSubtitle(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
