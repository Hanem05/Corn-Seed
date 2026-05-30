import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'camera_image_input.dart';

/// Single message for [compute] (must be one argument).
class JpegPreprocessArgs {
  JpegPreprocessArgs(this.bytes, this.inputShape);

  final Uint8List bytes;
  final List<int> inputShape;
}

/// Model input + layout for projection (no duplicate 640² float buffer on UI isolate).
class JpegPreprocessOutput {
  JpegPreprocessOutput({
    required this.modelInput,
    required this.layout,
  });

  final Float32List modelInput;
  final LetterboxLayout layout;
}

/// Top-level for [compute] — JPEG decode + letterbox + tensor packing off the UI thread.
JpegPreprocessOutput? jpegPreprocessForYolo(JpegPreprocessArgs args) {
  try {
    var decoded = img.decodeImage(args.bytes);
    if (decoded == null) return null;
    decoded = img.bakeOrientation(decoded);
    final lb = letterboxRgbImageToTensor(decoded);
    final input = tensorForInputShape(lb.tensorNhwc, args.inputShape);
    return JpegPreprocessOutput(
      modelInput: input,
      layout: lb.layout,
    );
  } catch (_) {
    return null;
  }
}
