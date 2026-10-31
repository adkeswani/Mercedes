import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stage5/app.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/presentation/climbing_completion_card.dart';
import 'package:stage5/main.dart' as app;

import 'support/browser_test_wait.dart';

const _testFile = 'integration_test/workout_climbing_canary_test.dart';
const _artifactPath = String.fromEnvironment('BROWSER_TEST_ARTIFACT_PATH',
    defaultValue: '<not provided>');
const _instanceId = 'browser-climbing-workout';
const _server = GetOptions(source: Source.server);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('trainer creates and edits both climbing block types via real UI',
      (tester) async {
    final waits = _waits(tester);
    await _login(tester, waits);
    _router(tester).go('/workouts/new');
    await _wait(
        tester, waits, find.text('New Workout Template'), 'creation form');
    await waits.runStep(
        'name climbing workout',
        () => tester.enterText(find.widgetWithText(TextField, 'Workout Name'),
            'Browser Climbing Authoring Canary'));
    await _tap(tester, waits, find.text('Create & Start Building'),
        'create workout header');
    await _wait(tester, waits, find.text('Publish'), 'builder ready');

    await _addBlock(tester, waits, 'Climbing Circuit');
    await _tap(tester, waits, find.text('Choose exercise'),
        'choose climbing exercise');
    await _wait(tester, waits, find.text('Boulder Problem'),
        'climbing exercise picker');
    await _tap(tester, waits, find.text('Boulder Problem').last,
        'select climbing exercise');
    await _selectGrade(
        tester, waits, find.byType(DropdownButtonFormField<String>).last, 'V2');
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Number of climbs').first,
        '3',
        'prescribe boulders');
    await _enter(
        tester,
        waits,
        find
            .widgetWithText(TextFormField, 'Max attempts per climb (optional)')
            .first,
        '2',
        'prescribe per-climb attempt cap');
    await _tap(tester, waits, find.text('Add climbing row'),
        'add rope prescription row');
    await _selectSystem(tester, waits,
        find.byType(DropdownButtonFormField<ClimbingGradingSystem>).last);
    await _selectGrade(tester, waits,
        find.byType(DropdownButtonFormField<String>).last, '5.13a');
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Number of climbs').last,
        '1',
        'prescribe rope climb');
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Trainer note (optional)'),
        'Circuit trainer note',
        'circuit trainer note');
    await _tap(tester, waits, find.widgetWithText(FilledButton, 'Save'),
        'save circuit');
    await _wait(tester, waits, find.text('Climbing Circuit · Boulder Problem'),
        'circuit card');

    await _addBlock(tester, waits, 'Free Climbing');
    expect(find.text('Choose exercise'), findsNothing);
    expect(find.text('Number of climbs'), findsNothing);
    expect(find.byType(DropdownButtonFormField<ClimbingGradingSystem>),
        findsNothing);
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Trainer note (optional)'),
        'Free trainer note',
        'free climbing trainer note only');
    await _tap(tester, waits, find.widgetWithText(FilledButton, 'Save'),
        'save free climbing');
    await _tap(
        tester, waits, find.text('Publish'), 'publish first immutable version');
    await _wait(tester, waits, find.text('Published version 1'),
        'first publish confirmation');

    final workoutId =
        _router(tester).routeInformationProvider.value.uri.pathSegments.last;
    final header = FirebaseFirestore.instance
        .collection('workoutTemplates')
        .doc(workoutId);
    final versionRef = header.collection('workoutTemplateVersions').doc('1');
    final first = await waits.runStep(
        'read first version from emulator', () => versionRef.get(_server));
    final data = first.data()!;
    expect(data['publishState'], 'published');
    expect(data['blockCount'], 2);
    expect(data['slotCount'], 2);
    final blocks = data['blocks'] as List;
    final circuit = blocks.first as Map;
    final free = blocks.last as Map;
    expect(circuit['type'], 'climbingCircuit');
    expect(circuit['rows'][0]['grade'], 'V2');
    expect(circuit['rows'][0]['climbs'], 3);
    expect(circuit['rows'][0]['maxAttemptsPerClimb'], 2);
    expect(circuit['rows'][1]['gradingSystem'], 'yds');
    expect(circuit['rows'][1]['grade'], '5.13a');
    expect(free['type'], 'freeClimbing');
    expect(free['notes'], 'Free trainer note');
    expect(free.containsKey('rows'), isFalse);
    for (final block in blocks) {
      final child = await waits.runStep(
          'verify persisted block ${block['blockId']}',
          () => versionRef
              .collection('workoutBlocks')
              .doc(block['blockId'] as String)
              .get(_server));
      expect(child.data(), block);
    }

    await _tap(tester, waits, find.byTooltip('Edit prescription').first,
        'edit circuit prescription');
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Number of climbs').first,
        '4',
        'change draft climb count');
    await _tap(tester, waits, find.widgetWithText(FilledButton, 'Save'),
        'save edited circuit');
    await _tap(tester, waits, find.text('Publish'), 'publish edited version');
    await _wait(tester, waits, find.text('Published version 2'),
        'second publish confirmation');
    final second = await waits.runStep(
        'read second version',
        () =>
            header.collection('workoutTemplateVersions').doc('2').get(_server));
    expect(second.data()!['blocks'][0]['rows'][0]['climbs'], 4);
    expect(second.data()!['blocks'][0]['rowIds'], circuit['rowIds']);
    expect(second.data()!['slotIds'], data['slotIds']);
    expect((await versionRef.get(_server)).data(), data);
    await waits.runStep('capture trainer climbing authoring',
        () => binding.takeScreenshot('trainer-climbing-authoring'));
  }, skip: browserSmokeConfig.identityRole != BrowserSmokeIdentityRole.trainer);

  testWidgets(
      'athlete recovers and completes circuit and optional free climbing rows',
      (tester) async {
    final waits = _waits(tester);
    await _login(tester, waits);
    final instanceRef = FirebaseFirestore.instance
        .collection('workoutInstances')
        .doc(_instanceId);
    final versionRef = FirebaseFirestore.instance
        .collection('workoutTemplates')
        .doc(_instanceId)
        .collection('workoutTemplateVersions')
        .doc('1');
    final before = await waits.runStep(
        'read pinned immutable prescription', () => versionRef.get(_server));
    _router(tester).go('/athlete/workouts/$_instanceId');
    await _wait(tester, waits, find.text('Complete Workout'),
        'climbing completion screen');
    expect(find.text('3 × V2 · Max 2 attempts per climb'), findsOneWidget);
    expect(find.text('1 × 5.13a'), findsOneWidget);
    expect(find.text('Attempts'), findsNothing);

    for (final row in ['row-boulder', 'row-rope']) {
      final scope = find.byKey(ValueKey(row));
      await _tap(
          tester,
          waits,
          find.descendant(of: scope, matching: find.byType(Checkbox)),
          'complete prescribed $row');
      await _selectRpe(
          tester,
          waits,
          find.descendant(
              of: scope, matching: find.byType(DropdownButtonFormField<int>)),
          row == 'row-boulder' ? 8 : 6);
    }
    await _enter(
        tester,
        waits,
        find.descendant(
            of: find.byKey(const ValueKey('row-boulder')),
            matching:
                find.widgetWithText(TextFormField, 'Row note (optional)')),
        'Controlled feet actual',
        'record circuit row note');

    await _scroll(tester, waits, find.text('Trainer note: Explore routes'), 250,
        'reveal free climbing card');
    final freeCard = find.ancestor(
        of: find.text('Trainer note: Explore routes'),
        matching: find.byType(ClimbingCompletionCard));
    await _tap(
        tester,
        waits,
        find.descendant(of: freeCard, matching: find.text('Add result row')),
        'add optional free result');
    await _selectSystem(
        tester,
        waits,
        find.descendant(
            of: freeCard,
            matching:
                find.byType(DropdownButtonFormField<ClimbingGradingSystem>)));
    await _selectGrade(
        tester,
        waits,
        find.descendant(
            of: freeCard,
            matching: find.byType(DropdownButtonFormField<String>)),
        '5.13a');
    await _enter(
        tester,
        waits,
        find.descendant(
            of: freeCard,
            matching: find.widgetWithText(TextFormField, 'Climbs completed')),
        '2',
        'record actual rope climbs');
    await _enter(
        tester,
        waits,
        find.descendant(
            of: freeCard,
            matching:
                find.widgetWithText(TextFormField, 'Row note (optional)')),
        'Two clean climbs',
        'record free row note');
    await _selectRpe(
        tester,
        waits,
        find.descendant(
            of: freeCard, matching: find.byType(DropdownButtonFormField<int>)),
        7);
    await _enter(
        tester,
        waits,
        find.descendant(
            of: freeCard,
            matching:
                find.widgetWithText(TextFormField, 'Climbing note (optional)')),
        'Enjoyed the routes',
        'record free climbing note');

    var serverDraftSaved = false;
    await waits.waitForCondition(
      condition: 'climbing inputs saved to real server draft',
      isSatisfied: () => serverDraftSaved,
      pump: () async {
        final draft = await instanceRef
            .collection('completionDrafts')
            .doc('current')
            .get(_server);
        if (draft.data()?['climbingSlotIds'] == null) {
          await tester.pump(const Duration(milliseconds: 100));
          return;
        }
        final children = instanceRef
            .collection('completionDrafts')
            .doc('current')
            .collection('climbingInputs');
        final freeInput = await children.doc('slot-free-climbing').get(_server);
        final circuitInput =
            await children.doc('slot-climbing-circuit').get(_server);
        final freeRows = freeInput.data()?['freeRows'] as List?;
        final circuitRows = circuitInput.data()?['circuitRows'] as List?;
        serverDraftSaved = freeRows?.isNotEmpty == true &&
            circuitRows?.isNotEmpty == true &&
            (freeRows!.first as Map)['climbs'] == '2' &&
            (circuitRows!.first as Map)['rpe'] == 8;
        await tester.pump(const Duration(milliseconds: 100));
      },
      pumpTimeout: const Duration(seconds: 5),
      timeout: const Duration(seconds: 20),
    );

    _router(tester).go('/athlete/today');
    await _wait(
        tester, waits, find.text('Complete Workout'), 'leave completion',
        absent: true);
    _router(tester).go('/athlete/workouts/$_instanceId');
    await _wait(tester, waits, find.text('Complete Workout'),
        'restore canonical completion route');
    final checkbox = find.descendant(
        of: find.byKey(const ValueKey('row-boulder')),
        matching: find.byType(Checkbox));
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    await _scroll(tester, waits, find.text('Trainer note: Explore routes'), 250,
        'reveal recovered free card');
    final count = find.descendant(
        of: freeCard,
        matching: find.widgetWithText(TextFormField, 'Climbs completed'));
    expect(tester.widget<TextFormField>(count).initialValue, '2');
    await waits.runStep('capture recovered climbing inputs',
        () => binding.takeScreenshot('athlete-climbing-recovery'));

    await _scroll(tester, waits, find.text('Mark as Completed'), 250,
        'reveal completion button');
    await _tap(tester, waits, find.text('Mark as Completed'),
        'submit climbing workout');
    await _wait(
        tester, waits, find.text('Complete Workout'), 'completed navigation',
        absent: true);
    final completed = await waits.runStep(
        'verify completed instance', () => instanceRef.get(_server));
    expect(completed.data()?['status'], 'completed');
    expect(completed.data()?['workoutTemplateVersion'], 1);
    final results = await waits.runStep('read immutable actuals',
        () => instanceRef.collection('slotResults').get(_server));
    final bySlot = {for (final doc in results.docs) doc.id: doc.data()};
    final circuit = bySlot['slot-climbing-circuit']!;
    expect(circuit['rowIds'], ['row-boulder', 'row-rope']);
    expect(circuit['circuitRows'][0]['completed'], isTrue);
    expect(circuit['circuitRows'][0]['rpe'], 8);
    expect(circuit['circuitRows'][0]['notes'], 'Controlled feet actual');
    expect(circuit['circuitRows'][1]['rpe'], 6);
    expect(circuit['attempts'], isNull);
    expect(circuit['sent'], isNull);
    expect(circuit['reps'], isNull);
    expect(bySlot['slot-free-climbing']!['freeRows'][0]['grade'], '5.13a');
    expect(bySlot['slot-free-climbing']!['freeRows'][0]['climbs'], 2);
    expect(bySlot['slot-free-climbing']!['rpe'], 7);
    expect(bySlot['slot-free-climbing-optional']!['freeRows'], isEmpty);
    expect((await versionRef.get(_server)).data(), before.data());
    expect(
        (await instanceRef
                .collection('completionDrafts')
                .doc('current')
                .get(_server))
            .exists,
        isFalse);
    expect(
        (await instanceRef
                .collection('completionDrafts')
                .doc('current')
                .collection('climbingInputs')
                .get(_server))
            .docs,
        isEmpty);

    _router(tester).go('/athlete/workouts/$_instanceId');
    await _wait(tester, waits, find.text('Workout Details'),
        'immutable completed detail');
    expect(find.text('3 × V2 · Max 2 attempts per climb'), findsOneWidget);
    expect(find.text('Completed · RPE 8 · Controlled feet actual'),
        findsOneWidget);
    expect(find.text('9 × V5 · Max 2 attempts per climb'), findsNothing);
    expect(find.text('Completed prescribed row'), findsNothing);
    await _scroll(tester, waits, find.text('2 × 5.13a · Two clean climbs'), 250,
        'free climbing history');
    await waits.runStep('capture completed climbing history',
        () => binding.takeScreenshot('athlete-climbing-history'));
  }, skip: browserSmokeConfig.identityRole != BrowserSmokeIdentityRole.athlete);
}

BrowserTestWaitContext _waits(WidgetTester tester) => BrowserTestWaitContext(
      identity: browserSmokeConfig.identityRole?.name ?? 'unconfigured',
      testFile: _testFile,
      artifactPath: _artifactPath,
      currentRoute: () => find.byType(Navigator).evaluate().isEmpty
          ? '<not mounted>'
          : _router(tester).routeInformationProvider.value.uri.toString(),
    );

GoRouter _router(WidgetTester tester) => GoRouter.of(
      tester.element(find.byKey(authenticatedAppEntryKey)),
    );

Future<void> _login(WidgetTester tester, BrowserTestWaitContext waits) async {
  await waits.runStep('initialize emulators', app.initializeMercedesApp,
      timeout: const Duration(seconds: 30));
  await waits.runStep('mount application',
      () => tester.pumpWidget(const ProviderScope(child: MercedesApp())));
  await _wait(
      tester, waits, find.byKey(browserSmokeLoginButtonKey), 'emulator login');
  await _tap(
      tester, waits, find.byKey(browserSmokeLoginButtonKey), 'submit login');
  await _wait(tester, waits, find.byKey(authenticatedAppEntryKey),
      'authenticated workspace');
}

Future<void> _wait(WidgetTester tester, BrowserTestWaitContext waits,
        Finder finder, String label,
        {bool absent = false}) =>
    waits.waitForCondition(
      condition: label,
      isSatisfied: () => finder.evaluate().isEmpty == absent,
      pump: () => tester.pump(const Duration(milliseconds: 100)),
      timeout: const Duration(seconds: 30),
      details: () =>
          'Visible: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(25).join(' | ')}',
    );

Future<void> _tap(WidgetTester tester, BrowserTestWaitContext waits,
        Finder finder, String label) =>
    waits.runStep(label, () async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 400));
    });

Future<void> _enter(WidgetTester tester, BrowserTestWaitContext waits,
        Finder finder, String value, String label) =>
    waits.runStep(label, () async {
      await tester.ensureVisible(finder);
      await tester.enterText(finder, value);
      await tester.pump(const Duration(milliseconds: 100));
    });

Future<void> _scroll(WidgetTester tester, BrowserTestWaitContext waits,
        Finder finder, double delta, String label) =>
    waits.runStep(
        label,
        () => tester.scrollUntilVisible(finder, delta,
            scrollable: find.byType(Scrollable).first, maxScrolls: 40));

Future<void> _addBlock(
    WidgetTester tester, BrowserTestWaitContext waits, String type) async {
  await _tap(tester, waits, find.widgetWithText(TextButton, 'Add'),
      'open block type menu');
  await _wait(tester, waits, find.text(type), '$type menu option');
  await _tap(tester, waits, find.text(type), 'choose $type');
}

Future<void> _selectSystem(
    WidgetTester tester, BrowserTestWaitContext waits, Finder finder) async {
  await _tap(tester, waits, finder, 'open grading system dropdown');
  await _tap(tester, waits, find.text('YDS (rope)').last, 'select YDS grading');
}

Future<void> _selectGrade(WidgetTester tester, BrowserTestWaitContext waits,
    Finder finder, String grade) async {
  await _tap(tester, waits, finder, 'open canonical grade dropdown');
  await waits.runStep(
      'reveal canonical grade $grade',
      () => tester.scrollUntilVisible(find.text(grade).last, 120,
          scrollable: find.byType(Scrollable).last, maxScrolls: 35));
  await _tap(
      tester, waits, find.text(grade).last, 'select canonical grade $grade');
}

Future<void> _selectRpe(WidgetTester tester, BrowserTestWaitContext waits,
    Finder finder, int rpe) async {
  await _tap(tester, waits, finder, 'open row RPE dropdown');
  await _tap(tester, waits, find.text('$rpe').last, 'record RPE $rpe');
}
