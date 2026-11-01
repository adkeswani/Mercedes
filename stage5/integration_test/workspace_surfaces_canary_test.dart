// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stage5/app.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/core/web_workspace/web_workspace_mode.dart';
import 'package:stage5/features/auth/presentation/web_workspace_shell.dart';
import 'package:stage5/main.dart' as app;

import 'support/browser_test_wait.dart';
import 'support/router_test_utils.dart';
import 'support/workspace_surface_scenarios.dart';

const _testFile = 'integration_test/workspace_surfaces_canary_test.dart';
const _artifactPath = String.fromEnvironment(
  'BROWSER_TEST_ARTIFACT_PATH',
  defaultValue: '<not provided>',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'workspace surfaces retain populated content and screenshot coverage',
      (tester) async {
    final role = browserSmokeConfig.identityRole;
    expect(role, isNotNull);
    final identity = role!.name;
    final waits = BrowserTestWaitContext(
      identity: identity,
      testFile: _testFile,
      artifactPath: _artifactPath,
      currentRoute: () => mountedAppRouter(tester)
          .routeInformationProvider
          .value
          .uri
          .toString(),
    );
    Future<void> wait(String label, bool Function() ready) =>
        waits.waitForCondition(
          condition: label,
          isSatisfied: ready,
          pump: () => tester.pump(const Duration(milliseconds: 100)),
          details: () => 'Visible: ${find.byType(Text).evaluate().map(
                (element) => (element.widget as Text).data,
              ).whereType<String>().take(25).join(' | ')}',
        );

    await waits.runStep(
      'initialize emulators',
      app.initializeMercedesApp,
      timeout: const Duration(seconds: 30),
    );
    await tester.pumpWidget(const ProviderScope(child: MercedesApp()));
    await wait(
      'emulator login',
      () => find.byKey(browserSmokeLoginButtonKey).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(browserSmokeLoginButtonKey));
    await wait(
      'authenticated application',
      () => find.byKey(authenticatedAppEntryKey).evaluate().isNotEmpty,
    );
    final mode = role == BrowserSmokeIdentityRole.trainer
        ? WebWorkspaceMode.trainer
        : WebWorkspaceMode.athlete;
    final modeControl = find.descendant(
      of: find.byKey(webWorkspaceModeSwitcherKey),
      matching: find.text(mode.label),
    );
    await wait('workspace switcher', () => modeControl.evaluate().isNotEmpty);
    await tester.tap(modeControl);
    await wait('authenticated workspace identity', () {
      final body = html.document.body;
      return find.byKey(authenticatedAppEntryKey).evaluate().isNotEmpty &&
          body?.getAttribute('data-browser-smoke-authenticated') ==
              browserSmokeConfig.email &&
          body?.getAttribute('data-browser-smoke-workspace') == identity &&
          body?.getAttribute('data-browser-smoke-account-identity') ==
              'Browser Smoke ${role == BrowserSmokeIdentityRole.trainer ? 'Trainer' : 'Athlete'}';
    });
    expect(
      mountedAppRouter(tester).routeInformationProvider.value.uri.path,
      mode.initialLocation,
    );

    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final surfaces = role == BrowserSmokeIdentityRole.trainer
        ? trainerWorkspaceSurfaces
        : athleteWorkspaceSurfaces;

    Future<void> openSurface(WorkspaceSurfaceScenario surface) async {
      mountedAppRouter(tester).go(surface.route);
      await wait('populated ${surface.route}', () {
        final attribute = 'data-browser-smoke-surface-${surface.marker}';
        final body = html.document.body;
        final state = body?.getAttribute(attribute);
        if (state != null && state != 'ready') {
          throw StateError('${surface.route} reported $state');
        }
        return mountedAppRouter(tester)
                    .routeInformationProvider
                    .value
                    .uri
                    .path ==
                surface.route &&
            state == 'ready' &&
            body?.getAttribute('$attribute-content') == surface.content;
      });
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('permission-denied'), findsNothing);
      expect(find.textContaining('Something went wrong'), findsNothing);
    }

    Future<void> toggle(String label) async {
      await wait('accessible $label', () => _control(label) != null);
      _control(label)!.click();
      await tester.pump(const Duration(milliseconds: 500));
      final replacement = label.startsWith('Collapse ')
          ? label.replaceFirst('Collapse ', 'Expand ')
          : label.replaceFirst('Expand ', 'Collapse ');
      await wait(
        'accessible $replacement',
        () => _control(replacement) != null,
      );
    }

    for (final surface in surfaces) {
      await openSurface(surface);
      for (final control in surface.controls.entries) {
        await wait(
          'accessible ${control.key}',
          () => _control(control.key) != null,
        );
        final element = _control(control.key)!;
        expect(
          element.getAttribute('aria-disabled') == 'true' ||
              element.hasAttribute('disabled'),
          control.value,
          reason: '${control.key} disabled state',
        );
      }
      final collapse = surface.collapseControl;
      if (collapse != null) {
        await toggle(collapse);
        await toggle(collapse.replaceFirst('Collapse ', 'Expand '));
      }
    }

    // Capture only after all functional checks, so a screenshot handshake
    // cannot strand an unfinished scenario.
    await waits.captureAfterAssertions('workspace screenshots', () async {
      mountedAppRouter(tester).go(mode.initialLocation);
      await tester.pump(const Duration(milliseconds: 500));
      await binding.takeScreenshot('$identity-header-identity');
      for (final surface in surfaces) {
        await openSurface(surface);
        final collapse = surface.collapseControl;
        if (collapse != null) {
          await toggle(collapse);
          await binding.takeScreenshot('${surface.screenshot}-collapsed');
          await toggle(collapse.replaceFirst('Collapse ', 'Expand '));
        }
        await binding.takeScreenshot(surface.screenshot);
      }
    });
  });
}

html.Element? _control(String label) {
  for (final element in html.document.querySelectorAll('[aria-label]')) {
    if ((element.getAttribute('aria-label') ?? '').contains(label)) {
      return element;
    }
  }
  return null;
}
