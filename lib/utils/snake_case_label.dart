/// `white_corn` → "White corn" for UI chips and snackbars.
String formatSnakeCaseLabel(String raw) {
  return raw
      .split('_')
      .map(
        (w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1).toLowerCase() : ''}',
      )
      .join(' ');
}
