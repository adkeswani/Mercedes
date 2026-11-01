import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stage5/app.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/exercises/presentation/exercise_media_widgets.dart';
import 'package:stage5/features/programs/data/program_repository.dart';
import 'package:stage5/features/programs/domain/program.dart';
import 'package:stage5/features/workouts/data/workout_completion_draft_repository.dart';
import 'package:stage5/features/workouts/data/workout_instance_repository.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/climbing_completion_card.dart';
import 'package:stage5/features/workouts/presentation/workout_completion_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/main.dart' as app;

import 'support/browser_test_wait.dart';
import 'support/dropdown_test_utils.dart';
import 'support/list_test_utils.dart';
import 'support/router_test_utils.dart';
import 'support/workout_draft_diagnostics.dart';

const _testFile = 'integration_test/workout_climbing_canary_test.dart';
const _artifactPath = String.fromEnvironment('BROWSER_TEST_ARTIFACT_PATH',
    defaultValue: '<not provided>');
const _instanceId = 'browser-climbing-workout';
const _circuitDrill = 'https://example.test/climbing-circuit-drill.mp4';
const _freeDrill = 'https://example.test/free-climbing-drill.mp4';
const _replacementDrill = 'https://example.test/replaced-circuit-drill.mp4';
const _server = GetOptions(source: Source.server);
WorkoutDraftDiagnostics _draftDiagnostics = WorkoutDraftDiagnostics();

void main() {
  _draftDiagnostics.record({'phase': 'execution-start'});
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
    expect(find.text('Attach instructions (optional)'), findsOneWidget);
    await selectClimbingGrade(
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
    await selectClimbingSystem(tester, waits,
        find.byType(DropdownButtonFormField<ClimbingGradingSystem>).last);
    await selectClimbingGrade(tester, waits,
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
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Video URL (optional)'),
        _circuitDrill,
        'attach optional circuit drill video');
    await _enter(
        tester,
        waits,
        find
            .widgetWithText(TextFormField, 'Work duration (seconds, optional)')
            .first,
        '3',
        'circuit row work countdown');
    await _enter(
        tester,
        waits,
        find
            .widgetWithText(TextFormField, 'Rest duration (seconds, optional)')
            .first,
        '2',
        'circuit row rest countdown');
    await _tap(tester, waits, find.widgetWithText(FilledButton, 'Save'),
        'save circuit');
    await _wait(tester, waits, find.text('Climbing Circuit'), 'circuit card');

    await _addBlock(tester, waits, 'Free Climbing');
    expect(find.text('Attach instructions'), findsNothing);
    expect(find.text('Attach instructions (optional)'), findsNothing);
    expect(find.text('Number of climbs'), findsNothing);
    expect(find.byType(DropdownButtonFormField<ClimbingGradingSystem>),
        findsNothing);
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Trainer note (optional)'),
        'Free trainer note',
        'free climbing trainer note only');
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Video URL (optional)'),
        _freeDrill,
        'attach optional free climbing drill video');
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Work duration (seconds, optional)'),
        '3',
        'overall free climbing work countdown');
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Rest duration (seconds, optional)'),
        '2',
        'overall free climbing rest countdown');
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
    expect(circuit['videoUrl'], _circuitDrill);
    expect(circuit['rows'][0]['workSeconds'], 3);
    expect(circuit['rows'][0]['restSeconds'], 2);
    expect(data['slots'][0]['exerciseId'], climbingCircuitExerciseId);
    expect(free['type'], 'freeClimbing');
    expect(free['notes'], 'Free trainer note');
    expect(free['videoUrl'], _freeDrill);
    expect(free['workSeconds'], 3);
    expect(free['restSeconds'], 2);
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
    await _tap(tester, waits, find.text('Attach instructions (optional)'),
        'link an optional drill exercise');
    await _wait(tester, waits, find.text('Boulder Problem'), 'exercise picker');
    await _tap(
        tester, waits, find.text('Boulder Problem').last, 'link exercise');
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Video URL (optional)'))
            .controller!
            .text,
        _circuitDrill);
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Number of climbs').first,
        '4',
        'change draft climb count');
    await _enter(
        tester,
        waits,
        find.widgetWithText(TextFormField, 'Video URL (optional)'),
        _replacementDrill,
        'replace drill in new immutable version');
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
    expect(second.data()!['blocks'][0]['videoUrl'], _replacementDrill);
    expect(second.data()!['blocks'][1]['videoUrl'], _freeDrill);
    expect(second.data()!['blocks'][0]['rowIds'], circuit['rowIds']);
    expect(second.data()!['slotIds'], data['slotIds']);
    expect(second.data()!['slots'][0]['exerciseName'], 'Boulder Problem');
    expect(second.data()!['slots'][0]['exerciseId'],
        isNot(climbingCircuitExerciseId));
    expect(second.data()!['blocks'][0]['rows'][0]['workSeconds'], 3);
    expect(second.data()!['blocks'][1]['restSeconds'], 2);
    expect((await versionRef.get(_server)).data(), data);
    final userId = data['ownerId'] as String;
    final programRepo = ProgramRepository();
    final programId = await waits.runStep(
        'create recurring climbing program',
        () => programRepo.create(
              name: 'Browser Recurring Climbing',
              type: ProgramType.assignable,
              userId: userId,
            ));
    final programVersion = await waits.runStep(
        'publish recurring climbing program with server propagation timestamp',
        () => programRepo.publishVersion(
              programId: programId,
              userId: userId,
              entries: [
                for (var i = 0; i < 4; i++)
                  ProgramScheduleEntry(
                    entryId: 'weekly-$i',
                    workoutTemplateId: workoutId,
                    workoutTemplateVersion: 1,
                    dayOffset: i * 7,
                    sortOrder: i,
                  ),
              ],
            ));
    expect(programVersion, 1);
    final publishedProgram = await waits.runStep(
        'verify recurring program persisted in emulator',
        () => FirebaseFirestore.instance
            .collection('programs')
            .doc(programId)
            .collection('programVersions')
            .doc('1')
            .get(_server));
    final programData = publishedProgram.data()!;
    expect(programData['entries'], hasLength(4));
    expect((programData['entries'] as List).map((entry) => entry['dayOffset']),
        [0, 7, 14, 21]);
    expect(programData['propagationState'], 'pending');
    expect(programData['propagationRequestedAt'], isA<Timestamp>());
    final instanceRepo = WorkoutInstanceRepository();
    final assignment = await waits.runStep(
        'assign weekly climbing program across daylight-saving change',
        () => instanceRepo.assignProgram(
              programId: programId,
              athleteId: userId,
              assignedBy: userId,
              startDate: '2026-11-01',
              relationshipMode: ProgramRelationshipMode.copied,
            ));
    final assigned = await waits.runStep(
        'verify weekly calendar dates in emulator',
        () => FirebaseFirestore.instance
            .collection('workoutInstances')
            .where('programAssignmentId', isEqualTo: assignment.assignmentId)
            .where('athleteId', isEqualTo: userId)
            .get(_server));
    final assignedDates = assigned.docs
        .map((doc) => doc.data()['scheduledDate'] as String)
        .toList()
      ..sort();
    expect(assignedDates,
        ['2026-11-01', '2026-11-08', '2026-11-15', '2026-11-22']);
    final recurringCount = await waits.runStep(
        'assign weekly workout recurrence across daylight-saving change',
        () => instanceRepo.assignRecurringWorkouts(
              programId: programId,
              athleteId: userId,
              assignedBy: userId,
              workoutTemplateId: workoutId,
              workoutTemplateVersion: 1,
              workoutType: WorkoutType.limit,
              startDate: '2026-11-01',
              recurrence: Recurrence(
                pattern: RecurrencePattern.weekly,
                daysOfWeek: [7],
                endDate: '2026-11-22',
              ),
            ));
    expect(recurringCount, 4);
    final recurring = await waits.runStep(
        'verify recurring workout calendar dates in emulator',
        () => FirebaseFirestore.instance
            .collection('workoutInstances')
            .where('programId', isEqualTo: programId)
            .where('athleteId', isEqualTo: userId)
            .get(_server));
    final recurringDates = recurring.docs
        .where((doc) => doc.data()['recurrence'] != null)
        .map((doc) => doc.data()['scheduledDate'] as String)
        .toList()
      ..sort();
    expect(recurringDates, assignedDates);
    await waits.captureAfterAssertions('capture trainer climbing authoring',
        () async {
      await binding.takeScreenshot('trainer-climbing-authoring');
    });
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
    await _wait(tester, waits, find.text('3 × V2 · Max 2 attempts per climb'),
        'pinned circuit prescription',
        reveal: true);
    expect(find.text('3 × V2 · Max 2 attempts per climb'), findsOneWidget);
    expect(find.text('1 × 5.13a'), findsOneWidget);
    await _expectDrillVideo(
        tester, waits, 'block-climbing-circuit', _circuitDrill);
    expect(find.text('Attempts'), findsNothing);
    await _runCountdown(tester, waits,
        'climbing-work-timer-block-climbing-circuit-row-boulder', 'work', 3);
    await _runCountdown(tester, waits,
        'climbing-rest-timer-block-climbing-circuit-row-boulder', 'rest', 2);
    expect(
        tester
            .widget<Checkbox>(find.descendant(
                of: find.byKey(const ValueKey<String>('row-boulder')),
                matching: find.byType(Checkbox)))
            .value,
        isFalse);

    for (final row in ['row-boulder', 'row-rope']) {
      final scope = find.byKey(ValueKey(row));
      await _tap(
          tester,
          waits,
          find.descendant(of: scope, matching: find.byType(Checkbox)),
          'complete prescribed $row');
      await selectClimbingRpe(
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
    await _expectDrillVideo(tester, waits, 'block-free-climbing', _freeDrill);
    await _runCountdown(
        tester, waits, 'climbing-work-timer-block-free-climbing', 'work', 3);
    await _runCountdown(
        tester, waits, 'climbing-rest-timer-block-free-climbing', 'rest', 2);
    final freeCard = find.ancestor(
        of: find.text('Trainer note: Explore routes'),
        matching: find.byType(ClimbingCompletionCard));
    await _tap(
        tester,
        waits,
        find.descendant(of: freeCard, matching: find.text('Add result row')),
        'add optional free result');
    await selectClimbingSystem(
        tester,
        waits,
        find.descendant(
            of: freeCard,
            matching:
                find.byType(DropdownButtonFormField<ClimbingGradingSystem>)));
    await selectClimbingGrade(
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
    await selectClimbingRpe(
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
    await _expectDrillVideo(
        tester, waits, 'block-climbing-circuit', _circuitDrill);
    final checkbox = find.descendant(
        of: find.byKey(const ValueKey('row-boulder')),
        matching: find.byType(Checkbox));
    await _wait(tester, waits, checkbox, 'recovered prescribed row',
        reveal: true);
    await waits.waitForCondition(
      condition: 'recovered prescribed row is completed',
      isSatisfied: () => checkbox
          .evaluate()
          .any((element) => (element.widget as Checkbox).value == true),
      pump: () => tester.pump(const Duration(milliseconds: 100)),
      timeout: const Duration(seconds: 20),
    );
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    await _scroll(tester, waits, find.text('Trainer note: Explore routes'), 250,
        'reveal recovered free card');
    await _expectDrillVideo(tester, waits, 'block-free-climbing', _freeDrill);
    final count = find.descendant(
        of: freeCard,
        matching: find.widgetWithText(TextFormField, 'Climbs completed'));
    await _wait(tester, waits, count, 'recovered free result count',
        reveal: true);
    await waits.waitForCondition(
      condition: 'recovered free result count is restored',
      isSatisfied: () => count.evaluate().any(
          (element) => (element.widget as TextFormField).initialValue == '2'),
      pump: () => tester.pump(const Duration(milliseconds: 100)),
      timeout: const Duration(seconds: 20),
    );
    expect(tester.widget<TextFormField>(count).initialValue, '2');
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
    await _wait(tester, waits, find.text('3 × V2 · Max 2 attempts per climb'),
        'completed pinned circuit prescription',
        reveal: true);
    expect(find.text('3 × V2 · Max 2 attempts per climb'), findsOneWidget);
    expect(find.text('Completed · RPE 8 · Controlled feet actual'),
        findsOneWidget);
    expect(find.text('9 × V5 · Max 2 attempts per climb'), findsNothing);
    await _expectDrillVideo(
        tester, waits, 'block-climbing-circuit', _circuitDrill);
    expect(find.text('Completed prescribed row'), findsNothing);
    await _scroll(tester, waits, find.text('2 × 5.13a · Two clean climbs'), 250,
        'free climbing history');
    await _expectDrillVideo(tester, waits, 'block-free-climbing', _freeDrill);
    await waits.captureAfterAssertions('capture completed climbing history',
        () async {
      await binding.takeScreenshot('athlete-climbing-history');
    });
  }, skip: browserSmokeConfig.identityRole != BrowserSmokeIdentityRole.athlete);
}

Future<void> _expectDrillVideo(WidgetTester tester,
        BrowserTestWaitContext waits, String blockId, String url) =>
    waits.runStep('verify pinned drill video $blockId', () async {
      final finder = find.descendant(
        of: find.byKey(WorkoutCompletionScreen.listKey),
        matching: find.byKey(ValueKey('climbing-video-$blockId')),
      );
      await _wait(tester, waits, finder, 'drill video $blockId', reveal: true);
      expect(finder, findsOneWidget);
      expect(tester.widget<ExerciseVideoPreview>(finder).url, url);
      expect(
          find.byWidgetPredicate((widget) =>
              widget is ExerciseVideoPreview &&
              widget.url == _replacementDrill),
          findsNothing);
    });

BrowserTestWaitContext _waits(WidgetTester tester) => BrowserTestWaitContext(
      identity: browserSmokeConfig.identityRole?.name ?? 'unconfigured',
      testFile: _testFile,
      artifactPath: _artifactPath,
      currentRoute: () => find.byType(Navigator).evaluate().isEmpty
          ? '<not mounted>'
          : _router(tester).routeInformationProvider.value.uri.toString(),
    );

GoRouter _router(WidgetTester tester) => mountedAppRouter(tester);

Future<void> _login(WidgetTester tester, BrowserTestWaitContext waits) async {
  await waits.runStep('initialize emulators', app.initializeMercedesApp,
      timeout: const Duration(seconds: 30));
  final diagnostics = WorkoutDraftDiagnostics();
  _draftDiagnostics = diagnostics;
  WorkoutCompletionDraftRepository.diagnosticObserver = diagnostics.record;
  WorkoutCompletionScreen.diagnosticObserver = diagnostics.record;
  addTearDown(() {
    WorkoutCompletionDraftRepository.diagnosticObserver = null;
    WorkoutCompletionScreen.diagnosticObserver = null;
  });
  await waits.runStep('mount application',
      () => tester.pumpWidget(const ProviderScope(child: MercedesApp())));
  await _wait(
      tester, waits, find.byKey(browserSmokeLoginButtonKey), 'emulator login');
  await _tap(
      tester, waits, find.byKey(browserSmokeLoginButtonKey), 'submit login');
  await _wait(tester, waits, find.byKey(authenticatedAppEntryKey),
      'authenticated workspace');
}

Future<void> _runCountdown(WidgetTester tester, BrowserTestWaitContext waits,
    String key, String label, int seconds) async {
  final timer = find.byKey(ValueKey<String>(key));
  await _wait(tester, waits, timer, '$key visible', reveal: true);
  await _tap(
      tester,
      waits,
      find.descendant(
          of: timer, matching: find.byTooltip('Start $label timer')),
      'start $key');
  await _wait(
      tester,
      waits,
      find.descendant(of: timer, matching: find.text('Time!')),
      '$key finished');
  await _tap(
      tester,
      waits,
      find.descendant(
          of: timer, matching: find.byTooltip('Reset $label timer')),
      'reset $key');
  expect(
      find.descendant(
          of: timer,
          matching: find.text('0:${seconds.toString().padLeft(2, '0')}')),
      findsOneWidget);
}

Future<void> _wait(WidgetTester tester, BrowserTestWaitContext waits,
    Finder finder, String label,
    {bool absent = false, bool reveal = false}) async {
  if (reveal) {
    await _wait(tester, waits, _workoutScrollables(), 'workout list ready');
    await waits.runStep('reveal $label', () => _reveal(tester, finder));
  }
  try {
    await waits.waitForCondition(
      condition: label,
      isSatisfied: () => finder.evaluate().isEmpty == absent,
      pump: () async {
        await tester.pump(const Duration(milliseconds: 100));
        if (label.startsWith('save settled before') &&
            find
                .descendant(
                  of: find.byKey(WorkoutCompletionScreen.listKey),
                  matching: find.text('Newer progress restored'),
                )
                .evaluate()
                .isNotEmpty) {
          final screen = find.byType(WorkoutCompletionScreen);
          final instanceId =
              tester.widget<WorkoutCompletionScreen>(screen).instanceId;
          final container = ProviderScope.containerOf(tester.element(screen));
          throw _draftDiagnostics.conflictFailure(
            workoutId: instanceId,
            currentClientId: container.read(workoutDraftClientIdProvider),
          );
        }
      },
      timeout: const Duration(seconds: 30),
      details: () =>
          'Visible: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(25).join(' | ')}',
    );
  } on WorkoutDraftConflictFailure catch (failure, stack) {
    _draftDiagnostics.failConflict(failure, stack);
  }
}

Finder _workoutScrollables() => find.descendant(
      of: find.byKey(WorkoutCompletionScreen.listKey),
      matching: find.byType(Scrollable),
    );

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (find.byType(WorkoutCompletionScreen).evaluate().isNotEmpty) {
    await revealListTarget(tester, finder,
        scrollable: _workoutScrollables().first);
  } else {
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, BrowserTestWaitContext waits,
        Finder finder, String label) =>
    waits.runStep(label, () async {
      await _reveal(tester, finder);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 400));
    });

Future<void> _enter(WidgetTester tester, BrowserTestWaitContext waits,
        Finder finder, String value, String label) =>
    waits.runStep(label, () async {
      await _reveal(tester, finder);
      await tester.enterText(finder, value);
      await tester.pump(const Duration(milliseconds: 100));
    });

Future<void> _scroll(WidgetTester tester, BrowserTestWaitContext waits,
        Finder finder, double delta, String label) =>
    waits.runStep(label, () async {
      await revealListTarget(tester, finder,
          scrollable: _workoutScrollables().first, delta: delta);
    });

Future<void> _addBlock(
    WidgetTester tester, BrowserTestWaitContext waits, String type) async {
  await _tap(tester, waits, find.widgetWithText(TextButton, 'Add'),
      'open block type menu');
  await _wait(tester, waits, find.text(type), '$type menu option');
  await _tap(tester, waits, find.text(type), 'choose $type');
}

@visibleForTesting
Future<void> selectClimbingSystem(
    WidgetTester tester, BrowserTestWaitContext waits, Finder finder) async {
  if (find.byType(WorkoutCompletionScreen).evaluate().isNotEmpty) {
    await _scroll(
        tester,
        waits,
        find.descendant(
          of: find.byKey(WorkoutCompletionScreen.listKey),
          matching: find.textContaining(RegExp(
              r'^(Saving\.\.\.|Saved|Offline — saved on this device|Save failed|Newer progress restored)$')),
        ),
        250,
        'reveal save status before grading');
    await _wait(
        tester,
        waits,
        find.descendant(
          of: find.byKey(WorkoutCompletionScreen.listKey),
          matching: find.text('Saved'),
        ),
        'save settled before grading');
  }
  await _tap(
      tester,
      waits,
      find.descendant(
          of: finder,
          matching: find.byType(DropdownButton<ClimbingGradingSystem>)),
      'open grading system dropdown');
  final option = await waits.runStep('reveal YDS grading',
      () => revealDropdownOption(tester, finder, ClimbingGradingSystem.yds));
  await waits.runStep('select YDS grading', () async {
    await tester.ensureVisible(option);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(option);
    await tester.pump(const Duration(milliseconds: 400));
    await _wait(tester, waits, option, 'grading popup dismissed', absent: true);
  });
}

@visibleForTesting
Future<void> selectClimbingGrade(WidgetTester tester,
    BrowserTestWaitContext waits, Finder finder, String grade) async {
  if (find.byType(WorkoutCompletionScreen).evaluate().isNotEmpty) {
    await _scroll(
        tester,
        waits,
        find.descendant(
          of: find.byKey(WorkoutCompletionScreen.listKey),
          matching: find.textContaining(RegExp(
              r'^(Saving\.\.\.|Saved|Offline — saved on this device|Save failed|Newer progress restored)$')),
        ),
        250,
        'reveal save status before grade');
    await _wait(
        tester,
        waits,
        find.descendant(
          of: find.byKey(WorkoutCompletionScreen.listKey),
          matching: find.text('Saved'),
        ),
        'save settled before grade');
  }
  await _tap(
      tester,
      waits,
      find.descendant(
          of: finder, matching: find.byType(DropdownButton<String>)),
      'open canonical grade dropdown');
  final option = await waits.runStep('reveal canonical grade $grade',
      () => revealDropdownOption(tester, finder, grade));
  await waits.runStep('select canonical grade $grade', () async {
    await tester.ensureVisible(option);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(option);
    await tester.pump(const Duration(milliseconds: 400));
    await _wait(tester, waits, option, 'grade popup dismissed', absent: true);
  });
}

@visibleForTesting
Future<void> selectClimbingRpe(WidgetTester tester,
    BrowserTestWaitContext waits, Finder finder, int rpe) async {
  if (find.byType(WorkoutCompletionScreen).evaluate().isNotEmpty) {
    await _scroll(
        tester,
        waits,
        find.descendant(
          of: find.byKey(WorkoutCompletionScreen.listKey),
          matching: find.textContaining(RegExp(
              r'^(Saving\.\.\.|Saved|Offline — saved on this device|Save failed|Newer progress restored)$')),
        ),
        250,
        'reveal save status before RPE');
    await _wait(
        tester,
        waits,
        find.descendant(
          of: find.byKey(WorkoutCompletionScreen.listKey),
          matching: find.text('Saved'),
        ),
        'save settled before RPE');
  }
  await _tap(
      tester,
      waits,
      find.descendant(of: finder, matching: find.byType(DropdownButton<int>)),
      'open row RPE dropdown');
  final option = await waits.runStep(
      'reveal RPE $rpe', () => revealDropdownOption(tester, finder, rpe));
  await waits.runStep('record RPE $rpe', () async {
    await tester.ensureVisible(option);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(option);
    await tester.pump(const Duration(milliseconds: 400));
    await _wait(tester, waits, option, 'RPE popup dismissed', absent: true);
  });
}
