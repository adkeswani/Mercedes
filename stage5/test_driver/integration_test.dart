import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  stdout.writeln('BROWSER_DRIVER|pid=$pid|'
      'sessionId=${Platform.environment['DRIVER_SESSION_ID']}|'
      'sessionUri=${Platform.environment['DRIVER_SESSION_URI']}');
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
