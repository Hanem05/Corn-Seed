import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';
import '../utils/camera_image_input.dart';

const String _kAsset = 'assets/models/viability5.tflite';

/// TFLite output order (training / MobileNetV3Large): **[non_viable, viable]**.
const List<String> kViabilityLabels = [
  'non_viable',
  'viable',
];

/// Rule requested: viable when confidence is >= 80%.
/// We use adjusted P(viable) from the 2-class output.
const double _kViableAcceptThreshold = 0.80;
const double _kMaxDefectPenalty = 0.28;

const int _kSize = 224;

/// [out][0] = non_viable, [out][1] = viable. Softmax if outputs look like logits.
(double nonViable, double viable) _twoClassProbabilities(Float32List out) {
  if (out.length < 2) {
    return (0.0, 0.0);
  }
  final s0 = out[0];
  final s1 = out[1];
  final sum = s0 + s1;
  final looksLikeSoftmax = sum >= 0.98 &&
      sum <= 1.02 &&
      s0 >= 0 &&
      s0 <= 1 &&
      s1 >= 0 &&
      s1 <= 1;
  if (looksLikeSoftmax) {
    return (s0, s1);
  }
  final m = s0 > s1 ? s0 : s1;
  final e0 = math.exp(s0 - m);
  final e1 = math.exp(s1 - m);
  final d = e0 + e1;
  return (e0 / d, e1 / d);
}

double _defectScore224(img.Image crop224) {
  final w = crop224.width;
  final h = crop224.height;
  final n = (w * h).clamp(1, 1 << 30);

  final luma = Uint8List(w * h);
  var darkCount = 0;
  var borderDarkCount = 0;
  var borderPx = 0;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final p = crop224.getPixel(x, y);
      final lv = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      luma[i] = lv;
      if (lv < 55) darkCount++;
      if (x < 8 || y < 8 || x >= w - 8 || y >= h - 8) {
        borderPx++;
        if (lv < 70) borderDarkCount++;
      }
    }
  }

  var strongEdgeCount = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final gx = (luma[y * w + (x + 1)] - luma[y * w + (x - 1)]).abs();
      final gy = (luma[(y + 1) * w + x] - luma[(y - 1) * w + x]).abs();
      if (gx + gy > 90) strongEdgeCount++;
    }
  }

  final darkRatio = darkCount / n;
  final edgeRatio = strongEdgeCount / n;
  final borderDarkRatio = borderPx > 0 ? borderDarkCount / borderPx : 0.0;

  var score = 0.0;
  // Holes/pits
  score += ((darkRatio - 0.05) / 0.20).clamp(0.0, 1.0) * 0.40;
  // Cracks/fracture texture
  score += ((edgeRatio - 0.09) / 0.30).clamp(0.0, 1.0) * 0.35;
  // Half/broken edge cue
  score += ((borderDarkRatio - 0.18) / 0.45).clamp(0.0, 1.0) * 0.25;
  return score.clamp(0.0, 1.0);
}

/// Rule: adjusted P(viable) >= 0.80 => viable, else non_viable.
(String label, double confidence) _decisionFromViabilityOutputs(
  Float32List outFlat, {
  img.Image? crop224,
}) {
  if (outFlat.length < 2) {
    return ('unknown', 0.0);
  }
  final p = _twoClassProbabilities(outFlat);
  var vi = p.$2;

  if (crop224 != null) {
    final defect = _defectScore224(crop224);
    vi -= defect * _kMaxDefectPenalty;
    vi = vi.clamp(0.0, 1.0);
  }

  // Confidence is always P(viable) (same scale as threshold).
  if (vi >= _kViableAcceptThreshold) {
    return ('viable', vi);
  }
  return ('non_viable', vi);
}

/// Match typical Keras `img_to_array` + float32 **0–255** (same as [smooth.py] / variety).
/// ImageNet mean/std here was wrong if you trained like smooth.py — that often pinned
/// outputs to one class (e.g. always `non_viable`).
/// Float32 **scalar** per channel (not uint8). Matches typical Keras `float32` image tensors.
double _viabilityRgbChannel(int value) =>
    value.toDouble().clamp(0.0, 255.0);

double _luma255(img.Pixel p) =>
    (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).clamp(0.0, 255.0);

/// 0.0 = **exact** YOLO letterbox-space crop: no outward padding, no inward inset.
const double _kViabilityTightInsetFrac = 0.0;

(int x0, int y0, int cw, int ch) _tightenCropRect(
  int x0,
  int y0,
  int cw,
  int ch,
  double insetFrac,
  int imgW,
  int imgH,
) {
  if (insetFrac <= 0 || insetFrac >= 1) {
    return (x0, y0, cw.clamp(1, imgW - x0), ch.clamp(1, imgH - y0));
  }
  final factor = 1.0 - insetFrac;
  var ncw = (cw * factor).round().clamp(1, cw);
  var nch = (ch * factor).round().clamp(1, ch);
  final cx = x0 + cw / 2.0;
  final cy = y0 + ch / 2.0;
  var nx0 = (cx - ncw / 2.0).round();
  var ny0 = (cy - nch / 2.0).round();
  if (nx0 < 0) {
    ncw += nx0;
    nx0 = 0;
  }
  if (ny0 < 0) {
    nch += ny0;
    ny0 = 0;
  }
  if (nx0 + ncw > imgW) ncw = imgW - nx0;
  if (ny0 + nch > imgH) nch = imgH - ny0;
  ncw = ncw.clamp(1, imgW - nx0);
  nch = nch.clamp(1, imgH - ny0);
  return (nx0, ny0, ncw, nch);
}

void _viabilityWorkerMain(List<Object?> args) {
  final mainSendPort = args[0] as SendPort;
  final modelBytes = args[1] as Uint8List;

  final inbox = ReceivePort();
  mainSendPort.send(inbox.sendPort);

  late final Interpreter interpreter;
  try {
    final opt = InterpreterOptions()..threads = 2;
    interpreter = Interpreter.fromBuffer(modelBytes, options: opt);
    opt.delete();
  } catch (e, st) {
    mainSendPort.send('error:$e\n$st');
    return;
  }

  final inTensor = interpreter.getInputTensor(0);
  final outTensor = interpreter.getOutputTensor(0);
  final inByteSize = inTensor.numBytes();
  final outByteSize = outTensor.numBytes();
  // NHWC float32 buffer; interpreter expects float bytes (via buffer view), never uint8 pixels.
  final inFlat = Float32List(inByteSize ~/ 4);
  final outFlat = Float32List(outByteSize ~/ 4);

  mainSendPort.send('ready');

  void run224(SendPort reply, img.Image resized224) {
    var k = 0;
    for (var y = 0; y < _kSize; y++) {
      for (var x = 0; x < _kSize; x++) {
        final p = resized224.getPixel(x, y);
        // Texture-focused input: use luminance and replicate to 3 channels.
        final l = _viabilityRgbChannel(_luma255(p).round());
        inFlat[k++] = l;
        inFlat[k++] = l;
        inFlat[k++] = l;
      }
    }

    final inBuf = inFlat.buffer.asUint8List(inFlat.offsetInBytes, inByteSize);
    final outBuf = outFlat.buffer.asUint8List(outFlat.offsetInBytes, outByteSize);
    interpreter.runForMultipleInputs([inBuf], {0: outBuf});

    final picked = _decisionFromViabilityOutputs(outFlat, crop224: resized224);
    reply.send(<Object?>[picked.$1, picked.$2]);
  }

  inbox.listen((Object? message) {
    if (message is! List) return;

    if (message.length == 2) {
      try {
        final reply = message[0] as SendPort;
        final jpegBytes = message[1] as Uint8List;
        final decoded = img.decodeImage(jpegBytes);
        if (decoded == null) {
          reply.send(null);
          return;
        }
        final rgb = img.bakeOrientation(decoded);
        final resized = img.copyResize(
          rgb,
          width: _kSize,
          height: _kSize,
          interpolation: img.Interpolation.linear,
        );
        run224(reply, resized);
      } catch (_) {
        try {
          (message[0] as SendPort).send(null);
        } catch (_) {}
      }
      return;
    }

    if (message.length < 8) return;
    try {
      final reply = message[0] as SendPort;
      final jpegBytes = message[1] as Uint8List;
      final boxFlat = message[2] as Float32List;
      final scale = message[3] as double;
      final padLeft = message[4] as double;
      final padTop = message[5] as double;

      final n = boxFlat.length ~/ 4;
      final decoded = img.decodeImage(jpegBytes);
      if (decoded == null) {
        reply.send(<List<Object?>>[]);
        return;
      }
      final rgb = img.bakeOrientation(decoded);

      final outList = <List<Object?>>[];
      for (var b = 0; b < n; b++) {
        final d = b * 4;
        final dx = boxFlat[d];
        final dy = boxFlat[d + 1];
        final dw = boxFlat[d + 2];
        final dh = boxFlat[d + 3];

        final left = ((dx - padLeft) / scale).round();
        final top = ((dy - padTop) / scale).round();
        var cw = (dw / scale).round();
        var ch = (dh / scale).round();

        var x0 = left.clamp(0, rgb.width - 1);
        var y0 = top.clamp(0, rgb.height - 1);
        cw = cw.clamp(1, rgb.width - x0);
        ch = ch.clamp(1, rgb.height - y0);

        final tight = _tightenCropRect(
          x0,
          y0,
          cw,
          ch,
          _kViabilityTightInsetFrac,
          rgb.width,
          rgb.height,
        );
        x0 = tight.$1;
        y0 = tight.$2;
        cw = tight.$3;
        ch = tight.$4;

        final crop = img.copyCrop(
          rgb,
          x: x0,
          y: y0,
          width: cw,
          height: ch,
        );
        final resized = img.copyResize(
          crop,
          width: _kSize,
          height: _kSize,
          interpolation: img.Interpolation.linear,
        );

        var kk = 0;
        for (var y = 0; y < _kSize; y++) {
          for (var x = 0; x < _kSize; x++) {
            final p = resized.getPixel(x, y);
            final l = _viabilityRgbChannel(_luma255(p).round());
            inFlat[kk++] = l;
            inFlat[kk++] = l;
            inFlat[kk++] = l;
          }
        }

        final inBuf = inFlat.buffer.asUint8List(inFlat.offsetInBytes, inByteSize);
        final outBuf = outFlat.buffer.asUint8List(outFlat.offsetInBytes, outByteSize);
        interpreter.runForMultipleInputs([inBuf], {0: outBuf});

        final picked = _decisionFromViabilityOutputs(outFlat, crop224: resized);
        outList.add([picked.$1, picked.$2]);
      }
      reply.send(outList);
    } catch (_) {
      try {
        (message[0] as SendPort).send(<List<Object?>>[]);
      } catch (_) {}
    }
  });
}

class ViabilityClassifier {
  Isolate? _isolate;
  SendPort? _workerSendPort;
  final ReceivePort _fromWorker = ReceivePort();

  Future<void> loadModel() async {
    final bd = await rootBundle.load(_kAsset);
    final modelBytes = bd.buffer.asUint8List(
      bd.offsetInBytes,
      bd.lengthInBytes,
    );

    final workerReady = Completer<void>();
    SendPort? workerIn;

    late final StreamSubscription<Object?> sub;
    sub = _fromWorker.listen((Object? message) {
      if (message is SendPort) {
        workerIn = message;
        return;
      }
      if (message is String) {
        if (message == 'ready') {
          workerReady.complete();
        } else if (message.startsWith('error:')) {
          workerReady.completeError(Exception(message.substring(6)));
        }
      }
    });

    _isolate = await Isolate.spawn(
      _viabilityWorkerMain,
      <Object?>[_fromWorker.sendPort, modelBytes],
    );
    await workerReady.future;
    await sub.cancel();

    _workerSendPort = workerIn;
  }

  Future<({String label, double confidence})?> classifyFullImage(
    Uint8List jpegBytes,
  ) async {
    final workerIn = _workerSendPort;
    if (workerIn == null) return null;

    final response = ReceivePort();
    workerIn.send(<Object?>[response.sendPort, jpegBytes]);
    final raw = await response.first;
    response.close();

    if (raw == null) return null;
    if (raw is List && raw.length >= 2) {
      final lab = raw[0];
      final cf = raw[1];
      if (lab is String && cf is num) {
        return (label: lab, confidence: cf.toDouble());
      }
    }
    return null;
  }

  Future<List<Detection>> attachViabilityLabels(
    Uint8List jpegBytes,
    List<Detection> detections,
    LetterboxLayout layout,
  ) async {
    final workerIn = _workerSendPort;
    if (workerIn == null || detections.isEmpty) {
      return detections;
    }

    final boxFlat = Float32List(detections.length * 4);
    for (var i = 0; i < detections.length; i++) {
      final d = detections[i];
      final o = i * 4;
      boxFlat[o] = d.x;
      boxFlat[o + 1] = d.y;
      boxFlat[o + 2] = d.w;
      boxFlat[o + 3] = d.h;
    }

    final response = ReceivePort();
    workerIn.send(<Object?>[
      response.sendPort,
      jpegBytes,
      boxFlat,
      layout.scale,
      layout.padLeft,
      layout.padTop,
      layout.srcWidth,
      layout.srcHeight,
    ]);
    final raw = await response.first;
    response.close();

    if (raw is! List) {
      return detections;
    }

    final out = <Detection>[];
    for (var i = 0; i < detections.length; i++) {
      final d = detections[i];
      String? label;
      double? vconf;
      if (i < raw.length && raw[i] is List) {
        final row = raw[i] as List;
        if (row.length >= 2) {
          label = row[0] as String?;
          final c = row[1];
          if (c is num) vconf = c.toDouble();
        }
      }
      out.add(
        Detection(
          x: d.x,
          y: d.y,
          w: d.w,
          h: d.h,
          confidence: d.confidence,
          viabilityLabel: label,
          viabilityConfidence: vconf,
        ),
      );
    }
    return out;
  }

  void dispose() {
    _fromWorker.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerSendPort = null;
  }
}
