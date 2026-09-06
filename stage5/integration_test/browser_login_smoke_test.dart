import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('local test account enters the authenticated app',
      (tester) async {
    expect(browserSmokeConfig.loginEnabled, isTrue);

    await app.main();
    await _pumpUntilFound(tester, find.byKey(browserSmokeLoginButtonKey));

    await tester.tap(find.byKey(browserSmokeLoginButtonKey));
    await _pumpUntilFound(tester, find.byKey(authenticatedAppEntryKey));

    expect(find.byKey(authenticatedAppEntryKey), findsOneWidget);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));

  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  throw TestFailure('Timed out waiting for browser smoke UI.');
}
