import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/app.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/core/routing/router.dart';
import 'package:stage5/core/web_workspace/pending_web_workspace_route.dart';
import 'package:stage5/core/web_workspace/web_workspace_mode.dart';
import 'package:stage5/core/web_workspace/web_workspace_preference.dart';
import 'package:stage5/features/auth/presentation/app_entry_providers.dart';
import 'package:stage5/features/auth/presentation/home_screen.dart';
import 'package:stage5/features/auth/presentation/web_workspace_shell.dart';

void main() {
  group('WebWorkspaceModeController', () {
    test('defaults to athlete when no preference exists', () {
      final preference = _FakeWebWorkspacePreference();
      final controller = WebWorkspaceModeController(preference);

      expect(controller.state, WebWorkspaceMode.athlete);
      expect(preference.writes, isEmpty);
    });

    test('restores a valid saved mode', () {
      final controller = WebWorkspaceModeController(
        _FakeWebWorkspacePreference('trainer'),
      );

      expect(controller.state, WebWorkspaceMode.trainer);
    });

    test('ignores an unknown saved value', () {
      final controller = WebWorkspaceModeController(
        _FakeWebWorkspacePreference('administrator'),
      );

      expect(controller.state, WebWorkspaceMode.athlete);
    });

    test('persists a changed mode without changing identity state', () {
      final preference = _FakeWebWorkspacePreference();
      final controller = WebWorkspaceModeController(preference);

      controller.select(WebWorkspaceMode.trainer);

      expect(controller.state, WebWorkspaceMode.trainer);
      expect(preference.writes, ['trainer']);
    });
  });

  group('PendingWebWorkspaceRoute', () {
    test('retains a namespaced deep link through authentication', () {
      final pendingRoute = PendingWebWorkspaceRoute(
        '/trainer/programs?selected=program-1',
      );

      expect(
        pendingRoute.take(),
        '/trainer/programs?selected=program-1',
      );
      expect(pendingRoute.take(), isNull);
    });

    test('ignores routes outside the web workspace namespaces', () {
      final pendingRoute = PendingWebWorkspaceRoute();

      pendingRoute.remember('/login');

      expect(pendingRoute.take(), isNull);
    });
  });

  group('responsive web workspace', () {
    testWidgets('shows both modes and switches to the other namespace',
        (tester) async {
      _setViewport(tester, const Size(1280, 800));
      final preference = _FakeWebWorkspacePreference();
      final container = _readyContainer(preference);
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      router.go('/athlete/progress');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MercedesApp(),
        ),
      );
      expect(find.byKey(authenticatedAppEntryKey), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.byKey(webWorkspaceModeSwitcherKey), findsOneWidget);
      expect(find.text('Athlete'), findsOneWidget);
      expect(find.text('Trainer'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('My calendar'), findsOneWidget);
      expect(find.text('My programs'), findsOneWidget);
      expect(find.text('Workout history'), findsOneWidget);
      expect(find.text('Progress'), findsNWidgets(2));
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Clients'), findsNothing);
      expect(find.text('Exercise library'), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/athlete/progress',
      );

      await tester.tap(find.text('Trainer'));
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        '/trainer/dashboard',
      );
      expect(find.text('Trainer dashboard'), findsOneWidget);
      expect(find.text('Clients'), findsOneWidget);
      expect(find.text('Exercise library'), findsOneWidget);
      expect(find.text('Workout library'), findsOneWidget);
      expect(find.text('Program library'), findsOneWidget);
      expect(find.text('Calendar & assignments'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      expect(find.text('My calendar'), findsNothing);
      expect(
        container.read(webWorkspaceModeProvider),
        WebWorkspaceMode.trainer,
      );
      expect(preference.writes, ['trainer']);
    });

    testWidgets('deep link selects and remembers its route mode',
        (tester) async {
      _setViewport(tester, const Size(1280, 800));
      final preference = _FakeWebWorkspacePreference();
      final container = _readyContainer(preference);
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      router.go('/trainer/dashboard');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MercedesApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trainer dashboard'), findsOneWidget);
      expect(
        container.read(webWorkspaceModeProvider),
        WebWorkspaceMode.trainer,
      );
      expect(preference.writes, ['trainer']);
    });

    testWidgets('athlete Today uses the namespaced calendar route',
        (tester) async {
      _setViewport(tester, const Size(1280, 800));
      final preference = _FakeWebWorkspacePreference();
      final container = _readyContainer(preference);
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      router.go('/athlete/today');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MercedesApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<HomeScreenContent>(find.byType(HomeScreenContent))
            .scheduleRoute,
        '/athlete/calendar',
      );
      expect(find.byKey(webWorkspaceModeSwitcherKey), findsOneWidget);
      expect(find.text('Athlete'), findsOneWidget);
      expect(find.text('Trainer'), findsOneWidget);
    });

    testWidgets('root restores the last selected web mode', (tester) async {
      _setViewport(tester, const Size(1280, 800));
      final preference = _FakeWebWorkspacePreference('trainer');
      final container = _readyContainer(preference);
      addTearDown(container.dispose);
      final router = container.read(routerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MercedesApp(),
        ),
      );
      expect(find.byKey(authenticatedAppEntryKey), findsOneWidget);
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        '/trainer/dashboard',
      );
      expect(find.text('Trainer dashboard'), findsOneWidget);
    });

    testWidgets('placeholder destinations provide useful empty-state copy',
        (tester) async {
      _setViewport(tester, const Size(1280, 800));
      final preference = _FakeWebWorkspacePreference();
      final container = _readyContainer(preference);
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      router.go('/athlete/messages');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MercedesApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Messages'), findsNWidgets(2));
      expect(
        find.text('Trainer and athlete conversations will be available here.'),
        findsOneWidget,
      );
    });

    testWidgets('mobile route keeps the existing fallback and hides the switch',
        (tester) async {
      _setViewport(tester, const Size(390, 844));
      final preference = _FakeWebWorkspacePreference();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webWorkspacePreferenceProvider.overrideWithValue(preference),
          ],
          child: const MaterialApp(
            home: AdaptiveWebWorkspaceRoute(
              mode: WebWorkspaceMode.trainer,
              destination: WebWorkspaceDestination.trainerDashboard,
              webChild: Text('desktop workspace'),
              mobileChild: Text(
                'existing mobile navigation',
                key: Key('mobile-fallback'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mobile-fallback')), findsOneWidget);
      expect(find.byKey(webWorkspaceModeSwitcherKey), findsNothing);
      expect(preference.writes, isEmpty);
    });

    testWidgets('signed-out web entry does not show the mode switch',
        (tester) async {
      _setViewport(tester, const Size(1280, 800));
      final container = ProviderContainer(
        overrides: [
          appEntryStateProvider.overrideWithValue(AppEntryState.signedOut),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MercedesApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.byKey(webWorkspaceModeSwitcherKey), findsNothing);
    });
  });
}

ProviderContainer _readyContainer(
  WebWorkspacePreference preference,
) {
  return ProviderContainer(
    overrides: [
      appEntryStateProvider.overrideWithValue(AppEntryState.ready),
      webWorkspacePreferenceProvider.overrideWithValue(preference),
    ],
  );
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _FakeWebWorkspacePreference implements WebWorkspacePreference {
  _FakeWebWorkspacePreference([this.value]);

  String? value;
  final List<String> writes = [];

  @override
  String? read() => value;

  @override
  void write(String mode) {
    value = mode;
    writes.add(mode);
  }
}
