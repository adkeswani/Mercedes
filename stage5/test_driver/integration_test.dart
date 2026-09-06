import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final outputDirectory = Directory(
    Platform.environment['BROWSER_SMOKE_ARTIFACT_DIR'] ??
        'test-artifacts${Platform.pathSeparator}browser-login',
  );
  await outputDirectory.create(recursive: true);

  await integrationDriver(
    onScreenshot: (
      String screenshotName,
      List<int> screenshotBytes, [
      Map<String, Object?>? args,
    ]) async {
      final screenshot = File(
        '${outputDirectory.path}${Platform.pathSeparator}'
        '$screenshotName.png',
      );
      await screenshot.writeAsBytes(screenshotBytes, flush: true);
      return true;
    },
    responseDataCallback: null,
  );
}
