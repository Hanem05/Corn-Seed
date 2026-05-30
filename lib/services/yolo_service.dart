import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';

const String _kAssetPath = 'assets/models/yolo-part2.tflite';

/// Pre-NMS candidate cutoff (very low = high recall in dense trays).
/// Keep extra weak candidates so adjacent seeds still survive to NMS.
const double _kCandidateConfThreshold = 0.01;

/// After NMS — keep low-confidence seeds for crowded scenes.
const double _kMinDrawConfidence = 0.03;

/// NMS IoU: very high to avoid suppressing nearby kernels.
const double _kNmsIou = 0.88;

/// Upper bound on detections for very dense captures.
const int _kNmsMaxBoxes = 1800;

double _conf(double raw) {
  if (raw >= 0 && raw <= 1.0) return raw;
  return 1.0 / (1.0 + math.exp(-raw.clamp(-80, 80)));
}

Map<String, double> _toBox640(
  double cx,
  double cy,
  double bw,
  double bh,
  double cf,
) {
  var xc = cx;
  var yc = cy;
  var w = bw;
  var hgt = bh;
  if (xc <= 1.5 && yc <= 1.5 && w <= 1.5 && hgt <= 1.5 && xc >= 0 && yc >= 0) {
    xc *= 640;
    yc *= 640;
    w *= 640;
    hgt *= 640;
  }
  final left = xc - w / 2;
  final top = yc - hgt / 2;
  return {
    'x': left.clamp(0, 640),
    'y': top.clamp(0, 640),
    'w': w.clamp(0, 640),
    'h': hgt.clamp(0, 640),
    'c': cf,
  };
}

List<Map<String, double>> _parseYoloOutputFlat(Float32List f, List<int> shape) {
  final maps = <Map<String, double>>[];

  if (shape.length == 3 && shape[0] == 1 && shape[1] == 5 && shape[2] == 8400) {
    const n = 8400;
    for (var j = 0; j < n; j++) {
      final cx = f[0 * n + j];
      final cy = f[1 * n + j];
      final bw = f[2 * n + j];
      final bh = f[3 * n + j];
      final cf = _conf(f[4 * n + j]);
      if (cf < _kCandidateConfThreshold) continue;
      maps.add(_toBox640(cx, cy, bw, bh, cf));
    }
    return maps;
  }

  if (shape.length == 3 && shape[0] == 1 && shape[1] == 8400 && shape[2] >= 5) {
    final nc = shape[2] - 4;
    const n = 8400;
    for (var j = 0; j < n; j++) {
      final cx = f[j * shape[2] + 0];
      final cy = f[j * shape[2] + 1];
      final bw = f[j * shape[2] + 2];
      final bh = f[j * shape[2] + 3];
      var best = 0.0;
      for (var k = 0; k < nc; k++) {
        final s = _conf(f[j * shape[2] + 4 + k]);
        if (s > best) best = s;
      }
      if (best < _kCandidateConfThreshold) continue;
      maps.add(_toBox640(cx, cy, bw, bh, best));
    }
    return maps;
  }

  if (shape.length == 3 && shape[0] == 1 && shape[2] == 5 && shape[1] > 100) {
    final n = shape[1];
    for (var j = 0; j < n; j++) {
      final cx = f[j * 5 + 0];
      final cy = f[j * 5 + 1];
      final bw = f[j * 5 + 2];
      final bh = f[j * 5 + 3];
      final cf = _conf(f[j * 5 + 4]);
      if (cf < _kCandidateConfThreshold) continue;
      maps.add(_toBox640(cx, cy, bw, bh, cf));
    }
    return maps;
  }

  if (shape.length == 3 &&
      shape[0] == 1 &&
      shape[1] > 5 &&
      shape[2] > 100 &&
      shape[1] < shape[2]) {
    final classes = shape[1] - 4;
    final n = shape[2];
    for (var j = 0; j < n; j++) {
      final cx = f[0 * n + j];
      final cy = f[1 * n + j];
      final bw = f[2 * n + j];
      final bh = f[3 * n + j];
      var best = 0.0;
      for (var c = 0; c < classes; c++) {
        final s = _conf(f[(4 + c) * n + j]);
        if (s > best) best = s;
      }
      if (best < _kCandidateConfThreshold) continue;
      maps.add(_toBox640(cx, cy, bw, bh, best));
    }
    return maps;
  }

  return maps;
}

double _iou(Map<String, double> a, Map<String, double> b) {
  final ax2 = a['x']! + a['w']!;
  final ay2 = a['y']! + a['h']!;
  final bx2 = b['x']! + b['w']!;
  final by2 = b['y']! + b['h']!;
  final ix1 = math.max(a['x']!, b['x']!);
  final iy1 = math.max(a['y']!, b['y']!);
  final ix2 = math.min(ax2, bx2);
  final iy2 = math.min(ay2, by2);
  final iw = math.max(0.0, ix2 - ix1);
  final ih = math.max(0.0, iy2 - iy1);
  final inter = iw * ih;
  final u = a['w']! * a['h']! + b['w']! * b['h']! - inter;
  return u > 0 ? inter / u : 0;
}

List<Map<String, double>> _nonMaxSuppression(
  List<Map<String, double>> boxes,
  double iouThresh,
  int maxOut,
) {
  if (boxes.isEmpty) return boxes;
  final sorted = List<Map<String, double>>.from(boxes)
    ..sort((a, b) => (b['c']!).compareTo(a['c']!));
  final out = <Map<String, double>>[];
  for (final b in sorted) {
    if (out.length >= maxOut) break;
    if (out.every((o) => _iou(o, b) < iouThresh)) {
      out.add(b);
    }
  }
  return out;
}

List<Map<String, double>> _applyDrawConfidenceFloor(
  List<Map<String, double>> boxes,
) {
  return boxes
      .where((b) => b['c']! >= _kMinDrawConfidence)
      .toList(growable: false);
}

class _RunRequest {
  _RunRequest(this.reply, this.input);
  final SendPort reply;
  final Float32List input;
}

void _yoloWorkerMain(List<Object?> args) {
  final mainSendPort = args[0] as SendPort;
  final modelBytes = args[1] as Uint8List;

  final inbox = ReceivePort();
  mainSendPort.send(inbox.sendPort);

  late final Interpreter interpreter;
  try {
    final opt = InterpreterOptions()..threads = 4;
    interpreter = Interpreter.fromBuffer(modelBytes, options: opt);
    opt.delete();
  } catch (e, st) {
    mainSendPort.send('error:$e\n$st');
    return;
  }

  final inTensor = interpreter.getInputTensor(0);
  final outTensor = interpreter.getOutputTensor(0);
  final inByteSize = inTensor.numBytes();
  final outBytes = Uint8List(outTensor.numBytes());
  final outShape = outTensor.shape;

  mainSendPort.send(
    'meta:${inTensor.shape.join("-")}|${outShape.join("-")}',
  );
  mainSendPort.send('ready');

  inbox.listen((Object? message) {
    if (message is! _RunRequest) return;
    try {
      final flat = message.input;
      if (flat.lengthInBytes != inByteSize) {
        message.reply.send(<Map<String, double>>[]);
        return;
      }
      final inBytes = flat.buffer.asUint8List(
        flat.offsetInBytes,
        flat.lengthInBytes,
      );
      interpreter.runForMultipleInputs([inBytes], {0: outBytes});

      final outEl = outBytes.length ~/ 4;
      final outView = outBytes.buffer.asFloat32List(
        outBytes.offsetInBytes,
        outEl,
      );
      final maps = _parseYoloOutputFlat(outView, outShape);
      final nms = _nonMaxSuppression(maps, _kNmsIou, _kNmsMaxBoxes);
      final out = _applyDrawConfidenceFloor(nms);
      message.reply.send(out);
    } catch (_) {
      message.reply.send(<Map<String, double>>[]);
    }
  });
}

/// TFLite runs in a **background isolate** so the UI thread stays responsive.
class YoloService {
  Isolate? _isolate;
  SendPort? _workerSendPort;
  final ReceivePort _fromWorker = ReceivePort();

  List<int>? inputTensorShape;

  Future<void> loadModel() async {
    final bd = await rootBundle.load(_kAssetPath);
    final modelBytes = bd.buffer.asUint8List(
      bd.offsetInBytes,
      bd.lengthInBytes,
    );

    final workerReady = Completer<void>();
    SendPort? workerIn;

    late final StreamSubscription sub;
    sub = _fromWorker.listen((Object? message) {
      if (message is SendPort) {
        workerIn = message;
        return;
      }
      if (message is String) {
        if (message.startsWith('meta:')) {
          final body = message.substring(5);
          final parts = body.split('|');
          if (parts.isNotEmpty) {
            inputTensorShape = parts[0].split('-').map(int.parse).toList();
          }
          return;
        }
        if (message == 'ready') {
          workerReady.complete();
        } else if (message.startsWith('error:')) {
          workerReady.completeError(Exception(message.substring(6)));
        }
      }
    });

    _isolate = await Isolate.spawn(
      _yoloWorkerMain,
      <Object?>[_fromWorker.sendPort, modelBytes],
    );
    await workerReady.future;
    await sub.cancel();

    _workerSendPort = workerIn;
  }

  Future<List<Detection>> runYOLO(Float32List input) async {
    final workerIn = _workerSendPort;
    if (workerIn == null) return [];

    final response = ReceivePort();
    workerIn.send(_RunRequest(response.sendPort, input));
    final raw = await response.first;
    response.close();

    if (raw is! List) return [];
    final out = <Detection>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      out.add(
        Detection(
          x: (m['x'] as num).toDouble(),
          y: (m['y'] as num).toDouble(),
          w: (m['w'] as num).toDouble(),
          h: (m['h'] as num).toDouble(),
          confidence: (m['c'] as num).toDouble(),
        ),
      );
    }
    out.sort((a, b) => b.confidence.compareTo(a.confidence));
    return out;
  }

  void dispose() {
    _fromWorker.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerSendPort = null;
  }
}
