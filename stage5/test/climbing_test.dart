import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/workouts/data/workout_instance_repository.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/climbing_completion_input.dart';
import 'package:stage5/features/workouts/domain/climbing_video.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

ExerciseSlot _slot(String id) => ExerciseSlot(
      slotId: id,
      exerciseId: 'climb-exercise',
      sortOrder: 0,
      mode: ExerciseMode.reps,
    );
ClimbingCircuitRow _row({
  String id = 'row-v',
  String grade = 'V2',
  int climbs = 3,
  int? attempts = 2,
  ClimbingGradingSystem system = ClimbingGradingSystem.vScale,
}) =>
    ClimbingCircuitRow(
      rowId: id,
      gradingSystem: system,
      grade: grade,
      climbs: climbs,
      maxAttemptsPerClimb: attempts,
      notes: 'Technique',
    );
ClimbingCircuitBlock _circuit(
        {List<ClimbingCircuitRow>? rows, String? videoUrl}) =>
    ClimbingCircuitBlock(
      blockId: 'circuit',
      sortOrder: 0,
      exercise: _slot('circuit-slot'),
      videoUrl: videoUrl,
      rows: rows ??
          [
            _row(),
            _row(
                id: 'row-yds',
                grade: '5.13a',
                system: ClimbingGradingSystem.yds)
          ],
    );
FreeClimbingBlock _free({String? videoUrl}) => FreeClimbingBlock(
      blockId: 'free',
      sortOrder: 1,
      slotId: 'free-slot',
      notes: 'Enjoy climbing',
      videoUrl: videoUrl,
    );

void main() {
  test('optional drill URLs are canonical and validated for both block types',
      () {
    const canonical = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
    expect(normalizeClimbingVideoUrl('https://youtu.be/dQw4w9WgXcQ?t=20'),
        canonical);
    expect(normalizeClimbingVideoUrl('https://example.test/drill.mp4#start'),
        'https://example.test/drill.mp4');
    expect(normalizeClimbingVideoUrl('  '), isNull);
    for (final value in [
      'javascript:alert(1)',
      'http://example.test/drill.mp4',
      'https://',
      'https://user:password@example.test/drill.mp4',
      'https://youtube.com/watch?v=invalid',
      'https://example.test/${'x' * maxClimbingVideoUrlLength}',
    ]) {
      expect(() => normalizeClimbingVideoUrl(value), throwsArgumentError);
    }
    for (final block in [
      _circuit(videoUrl: canonical),
      _free(videoUrl: canonical),
    ]) {
      expect(block.validate, returnsNormally);
      expect(block.copyWithSortOrder(3).videoUrl, canonical);
    }
    expect(_circuit(videoUrl: 'https://youtu.be/dQw4w9WgXcQ').validate,
        throwsArgumentError);
    expect(_free(videoUrl: 'not a URL').validate, throwsArgumentError);
  });
  test('canonical grades are explicitly ordered and rules use the same lists',
      () {
    expect(vScaleGrades.indexOf('V2'), lessThan(vScaleGrades.indexOf('V10')));
    expect(ydsGrades.indexOf('5.9'), lessThan(ydsGrades.indexOf('5.10a')));
    expect(ydsGrades.indexOf('5.13a'), lessThan(ydsGrades.indexOf('5.13d')));
    final rules = File('..\\firestore.rules').readAsStringSync();
    final gradeFunction = rules.substring(
      rules.indexOf('function climbingGrades()'),
      rules.indexOf('function validClimbingNote(data)'),
    );
    final ruleGrades = RegExp("'([^']+)'")
        .allMatches(gradeFunction)
        .map((m) => m.group(1))
        .where((g) => g != 'vScale' && g != 'yds')
        .toList();
    expect(ruleGrades, [...vScaleGrades, ...ydsGrades]);
    for (final system in ClimbingGradingSystem.values) {
      for (final grade in system.grades) {
        expect(() => validateClimbingGrade(system, grade), returnsNormally);
      }
    }
    for (final grade in ['Red', 'v2', 'V18', 'V2 ', '5.13', '5.13A']) {
      expect(() => validateClimbingGrade(ClimbingGradingSystem.vScale, grade),
          throwsArgumentError);
      expect(() => validateClimbingGrade(ClimbingGradingSystem.yds, grade),
          throwsArgumentError);
    }
    expect(() => parseGradingSystem('colors'), throwsFormatException);
  });

  test('circuit prescription validates grade, count, attempts and stable IDs',
      () {
    for (final row in [
      _row(id: ''),
      _row(id: 'bad/id'),
      _row(grade: 'Red'),
      _row(climbs: 0),
      _row(climbs: -1),
      _row(attempts: 0),
    ]) {
      expect(row.validate, throwsArgumentError);
    }
    expect(_row(attempts: null).validate, returnsNormally);
    expect(_circuit(rows: []).validate, throwsArgumentError);
    expect(_circuit(rows: [_row(), _row()]).validate, throwsArgumentError);
    expect(
        _circuit(rows: [for (var i = 0; i < 10; i++) _row(id: '$i')]).validate,
        throwsArgumentError);
    expect(ClimbingCircuitRow.fromMap(_row().toMap()).toMap(), _row().toMap());
  });

  test('rule grade patterns are equivalent to the canonical dropdown lists',
      () {
    final rules = File('..\\firestore.rules').readAsStringSync();
    final patterns = rules.substring(
      rules.indexOf('function climbingGradePatterns()'),
      rules.indexOf('function validClimbingGradeRow('),
    );
    final candidates = {
      ...vScaleGrades,
      ...ydsGrades,
      'Red',
      'VB ',
      'vb',
      for (var i = 0; i < 25; i++) ...[
        'V$i',
        'v$i',
        'V${i}a',
        'V$i ',
        for (final suffix in ['', 'a', 'b', 'c', 'd', 'A', '+', 'e'])
          '5.$i$suffix',
      ],
    };
    for (final system in ClimbingGradingSystem.values) {
      final pattern =
          RegExp("'${system.name}': '([^']+)'").firstMatch(patterns)!.group(1)!;
      for (final grade in candidates) {
        expect(RegExp(pattern).hasMatch(grade), system.grades.contains(grade),
            reason: '${system.name}: $grade');
      }
    }
  });

  test('result manifests reject missing, reordered and substituted row IDs',
      () {
    final actual =
        climbingActualFromInput(_circuit(), initialClimbingInput(_circuit()));
    for (final manifest in [
      null,
      ['row-v'],
      ['row-yds', 'row-v'],
      ['row-v', 'other'],
    ]) {
      expect(
          () => ExerciseActual.fromMap(
                {...actual.toMap(), 'rowIds': manifest},
                slotId: actual.slotId,
              ),
          throwsFormatException);
    }
  });

  test('recovery snapshots are copied and must match pinned type and row order',
      () {
    final input = initialClimbingInput(_circuit());
    final stored = climbingInputForStorage(input);
    (input['circuitRows'] as List).first['completed'] = true;
    expect((stored['circuitRows'] as List).first['completed'], isFalse);
    expect(
        () => validateClimbingInputForBlock(
            _circuit(), initialClimbingInput(_free())),
        throwsFormatException);
    stored['circuitRows'] = (stored['circuitRows'] as List).reversed.toList();
    stored.remove('rowIds');
    expect(() => validateClimbingInputForBlock(_circuit(), stored),
        throwsFormatException);
  });

  test('circuit rows are immutable and use one of nine slots', () {
    final source = [_row()];
    final block = _circuit(rows: source);
    source.clear();
    expect(block.rows.length, 1);
    expect(() => block.rows.add(_row()), throwsUnsupportedError);
    final nineRows =
        _circuit(rows: [for (var i = 0; i < 9; i++) _row(id: '$i')]);
    expect(nineRows.slots.length, 1);
    final version = WorkoutTemplateVersion(
      versionNumber: 1,
      publishedAt: DateTime.utc(2026),
      blocks: [
        nineRows,
        for (var i = 1; i < 9; i++)
          FreeClimbingBlock(
              blockId: 'free-$i', sortOrder: i, slotId: 'slot-$i'),
      ],
    );
    expect(version.validate, returnsNormally);
    expect(version.exerciseSlots.length, 9);
  });

  test(
      'canonical single routes need no color; unchanged legacy grades retain color',
      () {
    final route = ClimbingRouteBlock(
      blockId: 'route',
      sortOrder: 0,
      route: _slot('route-slot'),
      grade: '5.13a',
      gradingSystem: ClimbingGradingSystem.yds,
    );
    expect(route.validate, returnsNormally);
    final legacy = ClimbingRouteBlock(
      blockId: 'legacy',
      sortOrder: 0,
      route: _slot('legacy-slot'),
      grade: 'gym 6b+',
      color: 'Purple',
    );
    expect(legacy.validate, returnsNormally);
    expect(legacy.copyWithSortOrder(2).color, 'Purple');
    expect(legacy.copyWithSortOrder(2).grade, 'gym 6b+');
    expect(
        () => ClimbingRouteBlock(
              blockId: 'bad',
              sortOrder: 0,
              route: _slot('bad'),
              grade: 'V2',
              color: 'Red',
              gradingSystem: ClimbingGradingSystem.vScale,
            ).validate(),
        throwsArgumentError);
  });

  test('reorder and edit preserve block, slot and row IDs', () {
    final notifier = WorkoutDraftNotifier();
    addTearDown(notifier.dispose);
    notifier.addBlock(_circuit());
    notifier.addBlock(_free());
    notifier.reorder(0, 2);
    final circuit = notifier.state.last as ClimbingCircuitBlock;
    expect(circuit.blockId, 'circuit');
    expect(circuit.exercise.slotId, 'circuit-slot');
    expect(circuit.rows.map((r) => r.rowId), ['row-v', 'row-yds']);
    notifier.updateBlockAt(1, circuit);
    expect(notifier.state.last.sortOrder, 1);
    expect((notifier.state.last as ClimbingCircuitBlock).rows, circuit.rows);
  });

  test('circuit actuals have only completion, note and RPE for each pinned row',
      () {
    final block = _circuit();
    final input = initialClimbingInput(block);
    final rows = input['circuitRows'] as List;
    (rows.first as Map)['completed'] = true;
    (rows.first as Map)['rpe'] = 8;
    (rows.first as Map)['notes'] = 'Good';
    final actual = climbingActualFromInput(block, input);
    expect(actual.attempts, isNull);
    expect(actual.circuitRows!.last.completed, isFalse);
    expect(
        ExerciseActual.fromMap(actual.toMap(), slotId: actual.slotId).toMap(),
        actual.toMap());
    (rows.first as Map)['rowId'] = 'other';
    expect(() => climbingActualFromInput(block, input), throwsArgumentError);
  });

  test('free result rows are optional and have no prescribed attempts', () {
    final block = _free();
    expect(climbingActualFromInput(block, initialClimbingInput(block)).freeRows,
        isEmpty);
    final input = initialClimbingInput(block)..['rpe'] = 6;
    input['freeRows'] = <Map<String, dynamic>>[
      {
        'rowId': 'actual-row',
        'gradingSystem': 'yds',
        'grade': '5.13a',
        'climbs': '2',
        'notes': 'Two clean climbs',
      }
    ];
    final actual = climbingActualFromInput(block, input);
    expect(actual.freeRows!.single.climbs, 2);
    expect(actual.rpe, 6);
    expect(
        ExerciseActual.fromMap(actual.toMap(), slotId: actual.slotId)
            .freeRows!
            .single
            .grade,
        '5.13a');
    ((input['freeRows'] as List).first
        as Map<String, dynamic>)['maxAttemptsPerClimb'] = 3;
    expect(() => climbingActualFromInput(block, input), throwsFormatException);
  });

  test('invalid free count is preserved in drafts and rejected on completion',
      () {
    final block = _free();
    for (final count in ['', 'zero', '0', '-1', '1.5']) {
      final input = initialClimbingInput(block)
        ..['freeRows'] = [
          {
            'rowId': 'actual-row',
            'gradingSystem': 'vScale',
            'grade': 'V2',
            'climbs': count,
            'notes': '',
          }
        ];
      expect(() => validateClimbingInput(input), returnsNormally);
      expect(() => climbingActualFromInput(block, input), throwsArgumentError);
    }
  });

  test('row and free-block RPE reject values outside 1–10', () {
    for (final rpe in [0, 11, -1]) {
      expect(
          () => ClimbingCircuitResultRow(rowId: 'r', completed: true, rpe: rpe)
              .validate(),
          throwsArgumentError);
      final input = initialClimbingInput(_free())..['rpe'] = rpe;
      expect(
          () => climbingActualFromInput(_free(), input), throwsArgumentError);
    }
    for (final rpe in [null, 1, 10]) {
      expect(
          () => ClimbingCircuitResultRow(rowId: 'r', completed: false, rpe: rpe)
              .validate(),
          returnsNormally);
    }
  });

  test(
      'local and server draft codecs preserve row IDs, grades and unfinished input',
      () {
    final freeInput = initialClimbingInput(_free())
      ..['freeRows'] = [
        {
          'rowId': 'free-result',
          'gradingSystem': 'yds',
          'grade': '5.13a',
          'climbs': '',
          'notes': 'Still climbing',
        }
      ];
    final draft = WorkoutCompletionDraft(
      instanceId: 'instance',
      athleteId: 'athlete',
      rpe: 5,
      durationMinutes: 40,
      revision: 1,
      clientId: 'client',
      updatedAt: DateTime.utc(2026),
      sourceRoute: '/athlete/workouts/instance',
      slotInputs: {
        'circuit-slot': initialClimbingInput(_circuit()),
        'free-slot': freeInput
      },
    );
    final storedInputs = {
      for (final entry in draft.slotInputs.entries)
        entry.key: climbingInputForStorage(entry.value),
    };
    expect(WorkoutCompletionDraft.fromMap(draft.toLocalMap()).slotInputs,
        storedInputs);
    expect(
        WorkoutCompletionDraft.fromMap(draft.toMap()).slotInputs, storedInputs);
    (freeInput['freeRows'] as List).first['grade'] = 'Purple';
    expect(() => WorkoutCompletionDraft.fromMap(draft.toMap()),
        throwsFormatException);
  });

  group('repository climbing persistence', () {
    late FakeFirebaseFirestore firestore;
    late WorkoutTemplateRepository templates;
    late WorkoutInstanceRepository instances;
    setUp(() async {
      firestore = FakeFirebaseFirestore();
      templates = WorkoutTemplateRepository(firestore: firestore);
      instances = WorkoutInstanceRepository(firestore: firestore);
      await firestore
          .collection('exerciseTemplates')
          .doc('climb-exercise')
          .set({'createdBy': 'trainer'});
      await firestore.collection('workoutTemplates').doc('workout').set({
        'name': 'Climbing',
        'createdBy': 'trainer',
        'ownerId': 'trainer',
        'currentVersion': 0,
      });
      await templates
          .publishVersion(templateId: 'workout', userId: 'trainer', blocks: [
        _circuit(videoUrl: 'https://example.test/circuit-drill.mp4'),
        _free(videoUrl: 'https://example.test/free-drill.mp4'),
      ]);
      await firestore.collection('workoutInstances').doc('instance').set({
        'programId': 'program',
        'athleteId': 'athlete',
        'assignedBy': 'trainer',
        'workoutTemplateId': 'workout',
        'workoutTemplateVersion': 1,
        'scheduledDate': '2026-10-31',
        'status': 'scheduled',
        'actualsStorageFormat': 'slotResultsSubcollection',
        'actualSlotIds': <String>[],
      });
    });

    test('duplicate draft and republish retain both immutable drill videos',
        () async {
      final source = await templates.getLatestBlocks('workout');
      final duplicate = await templates.duplicateTemplate(
          sourceTemplateId: 'workout', userId: 'trainer');
      final draft = WorkoutDraftNotifier();
      addTearDown(draft.dispose);
      draft.load(source);
      draft.reorder(0, 2);
      await templates.publishVersion(
          templateId: duplicate, userId: 'trainer', blocks: draft.state);
      final copied = (await templates.getVersion(duplicate, 1))!;
      expect(copied.blocks.map((b) => b.videoUrl), [
        'https://example.test/free-drill.mp4',
        'https://example.test/circuit-drill.mp4',
      ]);
      expect((await templates.getVersion('workout', 1))!.blocks.first.videoUrl,
          'https://example.test/circuit-drill.mp4');
    });

    test('publish, decode and complete both blocks with immutable history',
        () async {
      final version = (await templates.getVersion('workout', 1))!;
      expect((version.blocks.first as ClimbingCircuitBlock).rows.last.grade,
          '5.13a');
      expect(version.blocks.last, isA<FreeClimbingBlock>());
      expect(version.blocks.first.videoUrl,
          'https://example.test/circuit-drill.mp4');
      expect(
          version.blocks.last.videoUrl, 'https://example.test/free-drill.mp4');
      final before = (await firestore
              .collection('workoutTemplates')
              .doc('workout')
              .collection('workoutTemplateVersions')
              .doc('1')
              .get())
          .data();
      final input = initialClimbingInput(version.blocks.first);
      (input['circuitRows'] as List).first['completed'] = true;
      (input['circuitRows'] as List).first['rpe'] = 7;
      await instances.completeWorkout(
        instanceId: 'instance',
        athleteId: 'athlete',
        rpe: 6,
        durationMinutes: 45,
        actuals: [
          climbingActualFromInput(version.blocks.first, input),
          climbingActualFromInput(
              version.blocks.last, initialClimbingInput(version.blocks.last)),
        ],
      );
      final completed = (await instances.getById('instance'))!;
      expect(completed.isCompleted, isTrue);
      expect(
          completed.actualsBySlot['circuit-slot']!.circuitRows!.first.rpe, 7);
      expect(completed.actualsBySlot['free-slot']!.freeRows, isEmpty);
      expect(
          (await firestore
                  .collection('workoutTemplates')
                  .doc('workout')
                  .collection('workoutTemplateVersions')
                  .doc('1')
                  .get())
              .data(),
          before);
      await templates
          .publishVersion(templateId: 'workout', userId: 'trainer', blocks: [
        _circuit(rows: [_row(grade: 'V5')]),
        _free(),
      ]);
      expect(
          (await templates.getVersion(
                  'workout', completed.workoutTemplateVersion))!
              .blocks
              .first,
          isA<ClimbingCircuitBlock>());
      expect(
          ((await templates.getVersion('workout', 1))!.blocks.first
                  as ClimbingCircuitBlock)
              .rows
              .first
              .grade,
          'V2');
      final pinned = (await templates.getVersion(
          'workout', completed.workoutTemplateVersion))!;
      expect(pinned.blocks.first.videoUrl,
          'https://example.test/circuit-drill.mp4');
      expect(
          pinned.blocks.last.videoUrl, 'https://example.test/free-drill.mp4');
      expect((await templates.getVersion('workout', 2))!.blocks.first.videoUrl,
          isNull);
    });

    test(
        'ownership, wrong row IDs, missing rows and extra actuals cannot complete',
        () async {
      final validFree =
          climbingActualFromInput(_free(), initialClimbingInput(_free()));
      final validCircuit =
          climbingActualFromInput(_circuit(), initialClimbingInput(_circuit()));
      await expectLater(
          instances.completeWorkout(
            instanceId: 'instance',
            athleteId: 'stranger',
            rpe: 5,
            durationMinutes: 20,
            actuals: [validCircuit, validFree],
          ),
          throwsStateError);
      for (final actuals in [
        [validFree],
        [validCircuit],
        [validCircuit, validFree, validFree],
        [
          ExerciseActual(
              slotId: 'circuit-slot',
              exerciseId: 'climb-exercise',
              mode: ExerciseMode.reps,
              attempts: 2),
          validFree
        ],
      ]) {
        await expectLater(
            instances.completeWorkout(
              instanceId: 'instance',
              athleteId: 'athlete',
              rpe: 5,
              durationMinutes: 20,
              actuals: actuals,
            ),
            throwsArgumentError);
      }
      expect((await instances.getById('instance'))!.isScheduled, isTrue);
    });

    test(
        'legacy arbitrary grade and color round trip unchanged alongside canonical routes',
        () async {
      await templates
          .publishVersion(templateId: 'workout', userId: 'trainer', blocks: [
        ClimbingRouteBlock(
            blockId: 'legacy',
            sortOrder: 0,
            route: _slot('legacy-slot'),
            grade: 'gym 6b+',
            color: 'Purple'),
        ClimbingRouteBlock(
            blockId: 'new',
            sortOrder: 1,
            route: _slot('new-slot'),
            grade: 'V2',
            gradingSystem: ClimbingGradingSystem.vScale),
      ]);
      final version = (await templates.getVersion('workout', 2))!;
      expect((version.blocks.first as ClimbingRouteBlock).grade, 'gym 6b+');
      expect((version.blocks.first as ClimbingRouteBlock).color, 'Purple');
      expect((version.blocks.last as ClimbingRouteBlock).gradingSystem,
          ClimbingGradingSystem.vScale);
    });
  });
}
