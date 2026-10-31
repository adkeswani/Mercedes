import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stage5/core/browser_smoke_config.dart';

import '../integration_test/support/router_test_utils.dart';

void main() {
  late GoRouter router;

  setUp(() {
    router = GoRouter(
      initialLocation: '/athlete/today',
      routes: [
        GoRoute(
          path: '/athlete/today',
          builder: (_, __) => const Scaffold(
            key: authenticatedAppEntryKey,
            body: Text('Today'),
          ),
        ),
        GoRoute(
          path: '/workouts/:id',
          builder: (_, __) => const Scaffold(body: Text('Workout builder')),
        ),
        GoRoute(
          path: '/athlete/workouts/:id',
          builder: (_, __) => const Scaffold(body: Text('Complete Workout')),
        ),
      ],
    );
  });
  tearDown(() => router.dispose());

  testWidgets('trainer router survives leaving the entry screen and a modal',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byKey(authenticatedAppEntryKey), findsOneWidget);
    expect(mountedAppRouter(tester), same(router));
    mountedAppRouter(tester).go('/workouts/router-test');
    await tester.pumpAndSettle();
    expect(find.byKey(authenticatedAppEntryKey), findsNothing);
    expect(mountedAppRouter(tester), same(router));
    expect(mountedAppRouter(tester).routeInformationProvider.value.uri.path,
        '/workouts/router-test');

    final dialog = showDialog<void>(
      context: tester.element(find.text('Workout builder')),
      builder: (_) => const AlertDialog(content: Text('Publishing')),
    );
    await tester.pumpAndSettle();
    expect(mountedAppRouter(tester), same(router));
    mountedAppRouter(tester).pop();
    await tester.pumpAndSettle();
    await dialog;
    expect(mountedAppRouter(tester).routeInformationProvider.value.uri.path,
        '/workouts/router-test');
  });

  testWidgets('athlete router survives completion and recovery navigation',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    for (final route in [
      '/athlete/workouts/instance',
      '/athlete/today',
      '/athlete/workouts/instance',
    ]) {
      mountedAppRouter(tester).go(route);
      await tester.pumpAndSettle();
      expect(mountedAppRouter(tester), same(router));
      expect(mountedAppRouter(tester).routeInformationProvider.value.uri.path,
          route);
      expect(find.byKey(authenticatedAppEntryKey),
          route == '/athlete/today' ? findsOneWidget : findsNothing);
    }
  });
}
