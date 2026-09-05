import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/programs/domain/athlete_program_instance.dart';

void main() {
  AthleteProgramInstance build({
    ProgramRelationshipMode mode = ProgramRelationshipMode.subscribed,
    DateTime? linkedAt,
    DateTime? unlinkedAt,
    String? unlinkReason,
  }) {
    final now = DateTime.utc(2026, 1, 1);
    return AthleteProgramInstance(
      id: 'instance-1',
      athleteOwnerId: 'athlete-1',
      assigningTrainerId: 'trainer-1',
      sourceProgramId: 'program-1',
      sourceProgramVersion: 3,
      relationshipMode: mode,
      startDate: '2026-01-01',
      expectedEndDate: '2026-02-01',
      workoutCount: 4,
      status: AthleteProgramInstanceStatus.active,
      linkedAt:
          linkedAt ?? (mode == ProgramRelationshipMode.subscribed ? now : null),
      unlinkedAt: unlinkedAt,
      unlinkReason: unlinkReason,
      createdAt: now,
      createdBy: 'trainer-1',
      updatedAt: now,
      updatedBy: 'trainer-1',
    );
  }

  test('valid subscribed instance remains linked', () {
    final instance = build();

    expect(instance.isLinked, isTrue);
    expect(instance.isCopied, isFalse);
    expect(instance.validate, returnsNormally);
  });

  test('valid unlinked copy retains unlink audit', () {
    final instance = build(
      mode: ProgramRelationshipMode.copied,
      linkedAt: null,
      unlinkedAt: DateTime.utc(2026, 1, 2),
      unlinkReason: 'structuralCustomization',
    );

    expect(instance.isLinked, isFalse);
    expect(instance.isCopied, isTrue);
    expect(instance.validate, returnsNormally);
  });

  test('subscription requires link timestamp', () {
    final now = DateTime.utc(2026, 1, 1);
    final instance = AthleteProgramInstance(
      id: 'instance-1',
      athleteOwnerId: 'athlete-1',
      assigningTrainerId: 'trainer-1',
      sourceProgramId: 'program-1',
      sourceProgramVersion: 1,
      relationshipMode: ProgramRelationshipMode.subscribed,
      startDate: '2026-01-01',
      expectedEndDate: '2026-01-01',
      workoutCount: 1,
      status: AthleteProgramInstanceStatus.active,
      createdAt: now,
      createdBy: 'trainer-1',
      updatedAt: now,
      updatedBy: 'trainer-1',
    );

    expect(instance.validate, throwsArgumentError);
  });

  test('end date cannot precede start date', () {
    final instance = build().copyForTest(
      startDate: '2026-02-01',
      expectedEndDate: '2026-01-01',
    );

    expect(instance.validate, throwsArgumentError);
  });
}

extension on AthleteProgramInstance {
  AthleteProgramInstance copyForTest({
    required String startDate,
    required String expectedEndDate,
  }) {
    return AthleteProgramInstance(
      id: id,
      athleteOwnerId: athleteOwnerId,
      assigningTrainerId: assigningTrainerId,
      sourceProgramId: sourceProgramId,
      sourceProgramVersion: sourceProgramVersion,
      relationshipMode: relationshipMode,
      startDate: startDate,
      expectedEndDate: expectedEndDate,
      workoutCount: workoutCount,
      status: status,
      linkedAt: linkedAt,
      unlinkedAt: unlinkedAt,
      unlinkReason: unlinkReason,
      createdAt: createdAt,
      createdBy: createdBy,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
    );
  }
}
