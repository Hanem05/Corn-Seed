import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corn_detector/main.dart';

void main() {
  testWidgets('MyApp builds and shows no-camera message when list is empty', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MyApp(cameras: <CameraDescription>[]),
    );
    await tester.pump();
    await tester.scrollUntilVisible(find.text('No camera found on this device.'), 200);

    expect(
      find.text('No camera found on this device.'),
      findsOneWidget,
    );
  });
}
