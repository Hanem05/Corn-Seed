import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';
import '../utils/camera_image_input.dart';
import '../utils/variety_prediction.dart';

export '../utils/variety_prediction.dart' show kCornVarietyLabels;

const String _kClassifierAsset = 'assets/models/variety_model.tflite';

const int _kClassifierInputSize = 224;

/// Match training with MobileNet include_preprocessing=True: feed 0..255.
double _classifierRgbChannel(int value) =>
    value.toDouble().clamp(0.0, 255.0);

/// `tf.image.resize` defaults to **bilinear**; match that (not nearest).
const img.Interpolation _kClassifierResizeInterpolation = img.Interpolation.linear;

/// Context padding around YOLO crop before 224² resize.
const double _kCropMarginFrac = 0.15;

(int x0, int y0, int cw, int ch) _expandCropRect(
  int x0,
  int y0,
  int cw,
  int ch,
  int imgW,
  int imgH,
) {
  final padW = (cw * _kCropMarginFrac).round();
  final padH = (ch * _kCropMarginFrac).round();
  var nx0 = x0 - padW;
  var ny0 = y0 - padH;
  var ncw = cw + 2 * padW;
  var nch = ch + 2 * padH;
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
  ncw = ncw.clamp(1, imgW);
  nch = nch.clamp(1, imgH);
  return (nx0, ny0, ncw, nch);
}

/// Message: [SendPort reply, Uint8List jpeg, Float32List xywh..., scale, padL, padT, srcW, srcH]
void _varietyWorkerMain(List<Object?> args) {
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
    inbox.close();
    mainSendPort.send('error:$e\n$st');
    return;
  }

  late final int inByteSize;
  late final int outByteSize;
  try {
    final inputs = interpreter.getInputTensors();
    final outputs = interpreter.getOutputTensors();
    if (inputs.length != 1 || outputs.length != 1 ||
        inputs.single.type != TensorType.float32 ||
        outputs.single.type != TensorType.float32 ||
        inputs.single.shape.join(',') != '1,224,224,3' ||
        outputs.single.shape.join(',') != '1,${kCornVarietyLabels.length}') {
      throw StateError('Expected float32 RGB [1,224,224,3] input and '
          '[1,${kCornVarietyLabels.length}] variety output.');
    }
    inByteSize = inputs.single.numBytes();
    outByteSize = outputs.single.numBytes();
  } catch (e, st) {
    interpreter.close();
    inbox.close();
    mainSendPort.send('error:$e\n$st');
    return;
  }
  final inFlat = Float32List(inByteSize ~/ 4);
  final outFlat = Float32List(outByteSize ~/ 4);

  mainSendPort.send('ready');

  void run224AndReply(
    SendPort reply,
    img.Image resized224,
  ) {
    void runOnResized(img.Image resized) {
      var k = 0;
      for (var y = 0; y < _kClassifierInputSize; y++) {
        for (var x = 0; x < _kClassifierInputSize; x++) {
          final p = resized.getPixel(x, y);
          inFlat[k++] = _classifierRgbChannel(p.r.toInt());
          inFlat[k++] = _classifierRgbChannel(p.g.toInt());
          inFlat[k++] = _classifierRgbChannel(p.b.toInt());
        }
      }

      final inBuf = inFlat.buffer.asUint8List(
        inFlat.offsetInBytes,
        inByteSize,
      );
      final outBuf = outFlat.buffer.asUint8List(
        outFlat.offsetInBytes,
        outByteSize,
      );
      interpreter.runForMultipleInputs([inBuf], {0: outBuf});
    }

    runOnResized(resized224);

    // Output is softmax probabilities from the exported graph — use argmax only.
    final bestI = bestVarietyIndex(outFlat);
    final bestV = outFlat[bestI];
    final label = bestI < kCornVarietyLabels.length
        ? kCornVarietyLabels[bestI]
        : 'unknown';
    reply.send(<Object?>[label, bestV]);
  }

  inbox.listen((Object? message) {
    if (message is! List) return;

    /// [reply, jpegBytes] only — classify whole image resized to 224² (sanity test).
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
          width: _kClassifierInputSize,
          height: _kClassifierInputSize,
          interpolation: _kClassifierResizeInterpolation,
        );
        run224AndReply(reply, resized);
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
        final expanded = _expandCropRect(x0, y0, cw, ch, rgb.width, rgb.height);
        x0 = expanded.$1;
        y0 = expanded.$2;
        cw = expanded.$3;
        ch = expanded.$4;

        final crop = img.copyCrop(
          rgb,
          x: x0,
          y: y0,
          width: cw,
          height: ch,
        );
        final resized = img.copyResize(
          crop,
          width: _kClassifierInputSize,
          height: _kClassifierInputSize,
          interpolation: _kClassifierResizeInterpolation,
        );

        var k = 0;
        for (var y = 0; y < _kClassifierInputSize; y++) {
          for (var x = 0; x < _kClassifierInputSize; x++) {
            final p = resized.getPixel(x, y);
            inFlat[k++] = _classifierRgbChannel(p.r.toInt());
            inFlat[k++] = _classifierRgbChannel(p.g.toInt());
            inFlat[k++] = _classifierRgbChannel(p.b.toInt());
          }
        }
        final inBuf = inFlat.buffer.asUint8List(
          inFlat.offsetInBytes,
          inByteSize,
        );
        final outBuf = outFlat.buffer.asUint8List(
          outFlat.offsetInBytes,
          outByteSize,
        );
        interpreter.runForMultipleInputs([inBuf], {0: outBuf});

        final avg = List<double>.generate(
          outFlat.length,
          (i) => outFlat[i],
          growable: false,
        );

        final bestI = bestVarietyIndex(avg);
        final bestV = avg[bestI];

        final label = bestI < kCornVarietyLabels.length
            ? kCornVarietyLabels[bestI]
            : 'unknown';
        outList.add([label, bestV, avg]);
      }
      reply.send(outList);
    } catch (_) {
      try {
        (message[0] as SendPort).send(<List<Object?>>[]);
      } catch (_) {}
    }
  });
}

/// MobileNetV3 TFLite on a background isolate; one forward pass per YOLO box.
class CornVarietyClassifier {
  Isolate? _isolate;
  SendPort? _workerSendPort;
  final ReceivePort _fromWorker = ReceivePort();

  Future<void> loadModel() async {
    final bd = await rootBundle.load(_kClassifierAsset);
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
      _varietyWorkerMain,
      <Object?>[_fromWorker.sendPort, modelBytes],
    );
    await workerReady.future;
    await sub.cancel();

    _workerSendPort = workerIn;
  }

  /// Runs MobileNet on the **whole** JPEG resized to 224² (no YOLO). Use to verify
  /// the classifier and preprocessing before relying on per-crop results.
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

  /// Classifies **only** the YOLO crop for each box (letterbox space → source pixels →
  /// 224²). No full-frame merge or color heuristics — variety is whatever the model
  /// outputs on the seed crop alone.
  Future<List<Detection>> attachVarietyLabels(
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
      List<double>? vprobs;
      if (i < raw.length && raw[i] is List) {
        final row = raw[i] as List;
        if (row.length >= 2) {
          label = row[0] as String?;
          final c = row[1];
          if (c is num) vconf = c.toDouble();
        }
        if (row.length >= 3 && row[2] is List) {
          final probsRow = row[2] as List;
          vprobs = probsRow
              .whereType<num>()
              .map((e) => e.toDouble())
              .toList(growable: false);
        }
      }
      out.add(
        Detection(
          x: d.x,
          y: d.y,
          w: d.w,
          h: d.h,
          confidence: d.confidence,
          varietyLabel: label,
          varietyConfidence: vconf,
          varietyProbs: vprobs,
          viabilityLabel: null,
          viabilityConfidence: null,
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
