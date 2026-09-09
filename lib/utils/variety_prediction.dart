/// Training class order confirmed by the model owner.
const List<String> kCornVarietyLabels = [
  'HYBRID-SWEET-CORN',
  'OPV-WHITE-CORN',
  'OPV-YELLOW-CORN',
  'PURPLE-KALIMPOS-CORN',
  'CGUARD-WHITE-CORN',
];

/// Select from every class; never substitute a lower-scoring enabled class.
int bestVarietyIndex(List<double> probabilities) {
  if (probabilities.length != kCornVarietyLabels.length ||
      probabilities.any((p) => !p.isFinite || p < 0 || p > 1)) {
    throw const FormatException('Expected five finite variety probabilities.');
  }
  final sum = probabilities.fold(0.0, (total, p) => total + p);
  if ((sum - 1).abs() > 0.02) {
    throw const FormatException(
      'Variety output must be softmax probabilities.',
    );
  }
  var best = 0;
  for (var i = 1; i < probabilities.length; i++) {
    if (probabilities[i] > probabilities[best]) best = i;
  }
  return best;
}
