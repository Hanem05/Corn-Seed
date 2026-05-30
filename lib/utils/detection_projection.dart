import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/detection.dart';
import 'camera_image_input.dart';

/// Fits [srcWidth]:[srcHeight] into [bounds] using [BoxFit.contain] geometry.
Rect imageRectContain(Size bounds, int srcWidth, int srcHeight) {
  final ar = srcWidth / srcHeight;
  final bw = bounds.width;
  final bh = bounds.height;
  if (bw <= 0 || bh <= 0) {
    return Rect.zero;
  }
  if (bw / bh > ar) {
    final h = bh;
    final w = h * ar;
    final left = (bw - w) / 2;
    return Rect.fromLTWH(left, 0, w, h);
  } else {
    final w = bw;
    final h = w / ar;
    final top = (bh - h) / 2;
    return Rect.fromLTWH(0, top, w, h);
  }
}

/// Center-crop mapping from still-capture normalized coords to preview-buffer
/// aspect (typical when preview is a crop of the same sensor as the JPEG).
void _captureNormToPreviewCover(
  double nx,
  double ny,
  double nw,
  double nh,
  double arCapture,
  double arPreview,
  List<double> out,
) {
  final corners = <Offset>[
    Offset(nx, ny),
    Offset(nx + nw, ny),
    Offset(nx + nw, ny + nh),
    Offset(nx, ny + nh),
  ];
  final mapped = <Offset>[];
  for (final c in corners) {
    double u;
    double v;
    if (arCapture > arPreview) {
      final fracW = arPreview / arCapture;
      final xOff = (1.0 - fracW) / 2.0;
      u = (c.dx - xOff) / fracW;
      v = c.dy;
    } else if (arCapture < arPreview) {
      final fracH = arCapture / arPreview;
      final yOff = (1.0 - fracH) / 2.0;
      u = c.dx;
      v = (c.dy - yOff) / fracH;
    } else {
      u = c.dx;
      v = c.dy;
    }
    mapped.add(Offset(u, v));
  }
  var minU = mapped[0].dx;
  var maxU = mapped[0].dx;
  var minV = mapped[0].dy;
  var maxV = mapped[0].dy;
  for (var i = 1; i < mapped.length; i++) {
    final m = mapped[i];
    minU = math.min(minU, m.dx);
    maxU = math.max(maxU, m.dx);
    minV = math.min(minV, m.dy);
    maxV = math.max(maxV, m.dy);
  }
  minU = minU.clamp(0.0, 1.0);
  minV = minV.clamp(0.0, 1.0);
  maxU = maxU.clamp(0.0, 1.0);
  maxV = maxV.clamp(0.0, 1.0);
  out[0] = minU;
  out[1] = minV;
  out[2] = (maxU - minU).clamp(1e-6, 1.0);
  out[3] = (maxV - minV).clamp(1e-6, 1.0);
}

Size _alignPreviewSizeToCapture(Size previewBuffer, int capW, int capH) {
  var pw = previewBuffer.width;
  var ph = previewBuffer.height;
  final capPortrait = capH > capW;
  final previewPortrait = ph > pw;
  if (capPortrait != previewPortrait) {
    final t = pw;
    pw = ph;
    ph = t;
  }
  return Size(pw, ph);
}

/// Maps letterbox space → normalized still image → [previewRect] in overlay space.
///
/// [previewRect] should be the **measured** [CameraPreview] bounds in the overlay
/// [Stack]. Optional [previewBufferSize] enables center-crop when JPEG and
/// preview aspects differ.
List<Detection> projectDetectionsToScreen(
  List<Detection> letterboxSpace,
  LetterboxLayout lb,
  Rect previewRect, {
  Size? previewBufferSize,
}) {
  final out = <Detection>[];
  final capW = lb.srcWidth.toDouble();
  final capH = lb.srcHeight.toDouble();
  final arCapture = capW / capH;

  double arPreview = arCapture;
  if (previewBufferSize != null &&
      previewBufferSize.width > 0 &&
      previewBufferSize.height > 0) {
    final aligned = _alignPreviewSizeToCapture(
      previewBufferSize,
      lb.srcWidth,
      lb.srcHeight,
    );
    arPreview = aligned.width / aligned.height;
  }

  final buf = List<double>.filled(4, 0);
  final useCover = previewBufferSize != null &&
      previewBufferSize.width > 0 &&
      previewBufferSize.height > 0 &&
      (arCapture - arPreview).abs() > 1e-4;

  for (final d in letterboxSpace) {
    final left = (d.x - lb.padLeft) / lb.scale;
    final top = (d.y - lb.padTop) / lb.scale;
    final w = d.w / lb.scale;
    final h = d.h / lb.scale;

    final nx = left / capW;
    final ny = top / capH;
    final nw = w / capW;
    final nh = h / capH;

    double px;
    double py;
    double pw;
    double ph;
    if (useCover) {
      _captureNormToPreviewCover(nx, ny, nw, nh, arCapture, arPreview, buf);
      px = buf[0];
      py = buf[1];
      pw = buf[2];
      ph = buf[3];
    } else {
      px = nx;
      py = ny;
      pw = nw;
      ph = nh;
    }

    out.add(
      Detection(
        x: previewRect.left + px * previewRect.width,
        y: previewRect.top + py * previewRect.height,
        w: pw * previewRect.width,
        h: ph * previewRect.height,
        confidence: d.confidence,
        varietyLabel: d.varietyLabel,
        varietyConfidence: d.varietyConfidence,
        varietyProbs: d.varietyProbs,
        viabilityLabel: d.viabilityLabel,
        viabilityConfidence: d.viabilityConfidence,
      ),
    );
  }
  return out;
}
