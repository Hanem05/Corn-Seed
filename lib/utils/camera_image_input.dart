import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

const int kModelInputSize = 640;

/// Projection-only letterbox geometry (no tensor). Use when the UI isolate only
/// needs to map boxes onto the preview.
class LetterboxLayout {
  const LetterboxLayout({
    required this.scale,
    required this.padLeft,
    required this.padTop,
    required this.srcWidth,
    required this.srcHeight,
  });

  final double scale;
  final double padLeft;
  final double padTop;
  final int srcWidth;
  final int srcHeight;
}

/// Letterboxed frame matching Ultralytics `letterbox()` (ratio + pad 114).
class LetterboxResult {
  LetterboxResult({
    required this.tensorNhwc,
    required this.scale,
    required this.padLeft,
    required this.padTop,
    required this.srcWidth,
    required this.srcHeight,
  });

  /// NHWC float32 [0,1], length 640×640×3 (row-major).
  final Float32List tensorNhwc;
  final double scale;
  final double padLeft;
  final double padTop;
  final int srcWidth;
  final int srcHeight;

  LetterboxLayout get layout => LetterboxLayout(
        scale: scale,
        padLeft: padLeft,
        padTop: padTop,
        srcWidth: srcWidth,
        srcHeight: srcHeight,
      );
}

/// Same letterbox as the live camera path, for a decoded RGB image (e.g. asset / gallery).
LetterboxResult letterboxRgbImageToTensor(img.Image rgb) {
  return _letterboxFromRgb(rgb);
}

/// Per-frame min–max stretch (0–255) so dim / uneven lighting behaves closer to
/// well-exposed training shots, without changing letterbox geometry.
img.Image _prepareRgbForModel(img.Image rgb) {
  final copy = rgb.clone();
  var out = img.normalize(copy, min: 0, max: 255);
  out = _adaptiveLowLightLift(out);
  return out;
}

double _meanLuma01(img.Image im) {
  var sum = 0.0;
  final n = (im.width * im.height).clamp(1, 1 << 30);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      final r = p.r.toDouble();
      final g = p.g.toDouble();
      final b = p.b.toDouble();
      sum += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
    }
  }
  return sum / n;
}

img.Image _adaptiveLowLightLift(img.Image im) {
  final mean = _meanLuma01(im);
  if (mean >= 0.35) return im;

  // Push dark scenes toward a safer mid-tone range without overblowing highlights.
  final target = 0.45;
  final gain = (target / (mean <= 0.001 ? 0.001 : mean)).clamp(1.0, 1.8);
  const gamma = 0.85; // <1 brightens shadows.

  final lut = List<int>.generate(256, (i) {
    final g = ((i / 255.0) * gain).clamp(0.0, 1.0);
    final y = math.pow(g, gamma).toDouble();
    return (y * 255.0).round().clamp(0, 255);
  }, growable: false);

  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      im.setPixelRgb(
        x,
        y,
        lut[p.r.toInt()],
        lut[p.g.toInt()],
        lut[p.b.toInt()],
      );
    }
  }
  return im;
}

/// Builds a 640² letterboxed tensor from the camera frame (Ultralytics-compatible).
/// [uiOrientation] should match [MediaQuery.orientationOf] so rotation matches the preview.
LetterboxResult letterboxCameraImageToTensor(
  CameraImage cameraImage,
  CameraController controller, {
  Orientation? uiOrientation,
}) {
  var rgb = _yuv420ToRgbImage(cameraImage);
  rgb = _alignBufferToPreviewOrientation(
    rgb,
    cameraImage,
    controller,
    uiOrientation,
  );
  return _letterboxFromRgb(rgb);
}

LetterboxResult _letterboxFromRgb(img.Image rgb) {
  rgb = _prepareRgbForModel(rgb);
  final w = rgb.width;
  final h = rgb.height;
  final scale = math.min(kModelInputSize / w, kModelInputSize / h);
  final newW = (w * scale).round();
  final newH = (h * scale).round();
  final resized = img.copyResize(
    rgb,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.linear,
  );

  final padLeft = ((kModelInputSize - newW) / 2).floor();
  final padTop = ((kModelInputSize - newH) / 2).floor();

  final canvas = img.Image(width: kModelInputSize, height: kModelInputSize);
  img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
  img.compositeImage(canvas, resized, dstX: padLeft, dstY: padTop);

  final out = Float32List(kModelInputSize * kModelInputSize * 3);
  var i = 0;
  for (var y = 0; y < kModelInputSize; y++) {
    for (var x = 0; x < kModelInputSize; x++) {
      final p = canvas.getPixel(x, y);
      out[i++] = p.r / 255.0;
      out[i++] = p.g / 255.0;
      out[i++] = p.b / 255.0;
    }
  }

  return LetterboxResult(
    tensorNhwc: out,
    scale: scale,
    padLeft: padLeft.toDouble(),
    padTop: padTop.toDouble(),
    srcWidth: w,
    srcHeight: h,
  );
}

/// Rotates the decoded frame so it matches what the model should see (same idea as OpenCV static images).
/// Uses [CameraDescription.sensorOrientation] so live frames align with your accurate Python/asset tests.
img.Image _alignBufferToPreviewOrientation(
  img.Image rgb,
  CameraImage raw,
  CameraController controller,
  Orientation? uiOrientation,
) {
  if (kIsWeb) return rgb;

  final portrait = uiOrientation == null
      ? (controller.value.deviceOrientation == DeviceOrientation.portraitUp ||
          controller.value.deviceOrientation == DeviceOrientation.portraitDown)
      : (uiOrientation == Orientation.portrait);

  if (defaultTargetPlatform == TargetPlatform.android) {
    final landscapeBuffer = raw.width > raw.height;
    final portraitBuffer = raw.width < raw.height;

    // Rear camera often delivers a landscape buffer while the UI is portrait.
    // +90° CW usually matches preview / hand-held photos used in training.
    if (portrait && landscapeBuffer) {
      return img.copyRotate(rgb, angle: 90);
    }
    if (!portrait && portraitBuffer) {
      return img.copyRotate(rgb, angle: 90);
    }
    if (!portrait && landscapeBuffer) {
      return rgb;
    }
    if (portrait && portraitBuffer) {
      return rgb;
    }
    if (!portrait && !landscapeBuffer) {
      return img.copyRotate(rgb, angle: -90);
    }
  }
  return rgb;
}

/// Android YUV_420_888 / NV21-style buffers using each plane’s row + pixel stride.
img.Image _yuv420ToRgbImage(CameraImage image) {
  final width = image.width;
  final height = image.height;
  final out = img.Image(width: width, height: height);

  final yPlane = image.planes[0];
  final yBytes = yPlane.bytes;
  final yRowStride = yPlane.bytesPerRow;
  final yPix = yPlane.bytesPerPixel ?? 1;

  if (image.planes.length >= 3) {
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;
    final uRowStride = uPlane.bytesPerRow;
    final vRowStride = vPlane.bytesPerRow;
    final uPix = uPlane.bytesPerPixel ?? 1;
    final vPix = vPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final yIndex = y * yRowStride + x * yPix;
        final cx = x >> 1;
        final cy = y >> 1;
        final uIndex = cy * uRowStride + cx * uPix;
        final vIndex = cy * vRowStride + cx * vPix;
        if (yIndex >= yBytes.length ||
            uIndex >= uBytes.length ||
            vIndex >= vBytes.length) {
          continue;
        }
        final yp = yBytes[yIndex];
        final up = uBytes[uIndex];
        final vp = vBytes[vIndex];
        final rgb = _yuvToRgb(yp, up, vp);
        out.setPixelRgb(x, y, rgb[0], rgb[1], rgb[2]);
      }
    }
  } else {
    final uvPlane = image.planes[1];
    final uvBytes = uvPlane.bytes;
    final uvRowStride = uvPlane.bytesPerRow;
    final uvPix = uvPlane.bytesPerPixel ?? 2;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final yIndex = y * yRowStride + x * yPix;
        final cx = x >> 1;
        final cy = y >> 1;
        final uvIndex = cy * uvRowStride + cx * uvPix;
        if (yIndex >= yBytes.length || uvIndex + 1 >= uvBytes.length) {
          continue;
        }
        final yp = yBytes[yIndex];
        // NV21: V then U in interleaved chroma (typical Android image stream).
        final vp = uvBytes[uvIndex];
        final up = uvBytes[uvIndex + 1];
        final rgb = _yuvToRgb(yp, up, vp);
        out.setPixelRgb(x, y, rgb[0], rgb[1], rgb[2]);
      }
    }
  }

  return out;
}

List<int> _yuvToRgb(int y, int u, int v) {
  final yf = y.toDouble();
  final uf = u - 128.0;
  final vf = v - 128.0;
  var r = (yf + 1.402 * vf).round();
  var g = (yf - 0.344136 * uf - 0.714136 * vf).round();
  var b = (yf + 1.772 * uf).round();
  r = r.clamp(0, 255);
  g = g.clamp(0, 255);
  b = b.clamp(0, 255);
  return [r, g, b];
}

/// Converts NHWC to NCHW [1,3,640,640] flat buffer for some TFLite exports.
Float32List nhwcToNchw(Float32List nhwc, int h, int w) {
  final plane = h * w;
  final out = Float32List(3 * plane);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final j = (y * w + x) * 3;
      final r = nhwc[j];
      final g = nhwc[j + 1];
      final b = nhwc[j + 2];
      final o = y * w + x;
      out[o] = r;
      out[plane + o] = g;
      out[2 * plane + o] = b;
    }
  }
  return out;
}

/// Packs tensor for the interpreter’s expected flat layout.
Float32List tensorForInputShape(Float32List nhwc, List<int> shape) {
  if (shape.length == 4 &&
      shape[0] == 1 &&
      shape[1] == 3 &&
      shape[2] == kModelInputSize &&
      shape[3] == kModelInputSize) {
    return nhwcToNchw(nhwc, kModelInputSize, kModelInputSize);
  }
  if (shape.length == 4 &&
      shape[0] == 1 &&
      shape[1] == kModelInputSize &&
      shape[2] == kModelInputSize &&
      shape[3] == 3) {
    return nhwc;
  }
  return nhwc;
}
