class Detection {
  final double x;
  final double y;
  final double w;
  final double h;
  final double confidence;

  /// Variety model label (e.g. OPV-Yellow_Corn); set in variety scan mode.
  final String? varietyLabel;

  /// Classifier confidence for [varietyLabel].
  final double? varietyConfidence;
  
  /// Optional per-class probabilities for variety in model label order.
  final List<double>? varietyProbs;

  /// Viability model label (e.g. viable); set in viability scan mode.
  final String? viabilityLabel;

  /// Adjusted viability score (same scale as the 80% cutoff after defect penalty).
  final double? viabilityConfidence;

  Detection({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.confidence,
    this.varietyLabel,
    this.varietyConfidence,
    this.varietyProbs,
    this.viabilityLabel,
    this.viabilityConfidence,
  });
}
