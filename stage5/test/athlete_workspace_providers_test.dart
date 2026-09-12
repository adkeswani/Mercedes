import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/programs/data/athlete_program_instance_repository.dart';
import 'package:stage5/features/programs/domain/athlete_program_instance.dart';
import 'package:stage5/features/programs/presentation/athlete_program_instance_providers.dart';
import 'package:stage5/features/workouts/data/workout_instance_repository.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';

void main() {
  test(
    'athlete calendar provider scopes the query to the signed-in user',
    () async {
      final repository = _RecordingWorkoutRepository();
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_FakeUser('athlete-1')),
          ),
          workoutInstanceRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authStateProvider.future);
      const range = DateRange(startDate: '2026-01-01', endDate: '2026-01-07');

      await container.read(athleteScheduleProvider(range).future);

      expect(repository.scheduleAthleteId, 'athlete-1');
      expect(repository.scheduleStartDate, range.startDate);
      expect(repository.scheduleEndDate, range.endDate);
    },
  );

  test('athlete calendar provider preserves repository errors', () async {
    final repository = _RecordingWorkoutRepository(
      scheduleError: StateError('permission-denied'),
    );
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(_FakeUser('athlete-1')),
        ),
        workoutInstanceRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);

    await expectLater(
      container.read(
        athleteScheduleProvider(
          const DateRange(startDate: '2026-01-01', endDate: '2026-01-07'),
        ).future,
      ),
      throwsStateError,
    );
  });

  test('history provider scopes the query to the signed-in user', () async {
    final repository = _RecordingWorkoutRepository();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(_FakeUser('athlete-1')),
        ),
        workoutInstanceRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);

    await container.read(athleteWorkoutHistoryProvider.future);

    expect(repository.historyAthleteId, 'athlete-1');
  });

  test('program instances load while legacy backfill is pending', () async {
    final repository = _RecordingAthleteProgramRepository();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(_FakeUser('athlete-1')),
        ),
        athleteProgramInstanceRepositoryProvider.overrideWithValue(repository),
        myAthleteProgramInstanceBackfillStatusProvider.overrideWithValue(
          const AsyncLoading(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);

    expect(
      await container.read(myAthleteProgramInstancesProvider.future),
      isEmpty,
    );
    expect(repository.athleteId, 'athlete-1');
  });
}

class _FakeUser extends Fake implements User {
  _FakeUser(this._uid);

  final String _uid;

  @override
  String get uid => _uid;
}

class _RecordingWorkoutRepository extends WorkoutInstanceRepository {
  _RecordingWorkoutRepository({this.scheduleError})
      : super(firestore: FakeFirebaseFirestore());

  final Object? scheduleError;
  String? scheduleAthleteId;
  String? scheduleStartDate;
  String? scheduleEndDate;
  String? historyAthleteId;

  @override
  Stream<List<WorkoutInstance>> watchSchedule({
    required String athleteId,
    required String startDate,
    required String endDate,
  }) {
    scheduleAthleteId = athleteId;
    scheduleStartDate = startDate;
    scheduleEndDate = endDate;
    if (scheduleError != null) {
      return Stream.error(scheduleError!);
    }
    return Stream.value(const []);
  }

  @override
  Stream<List<WorkoutInstance>> watchHistory({required String athleteId}) {
    historyAthleteId = athleteId;
    return Stream.value(const []);
  }
}

class _RecordingAthleteProgramRepository
    extends AthleteProgramInstanceRepository {
  _RecordingAthleteProgramRepository()
      : super(firestore: FakeFirebaseFirestore());

  String? athleteId;

  @override
  Stream<List<AthleteProgramInstance>> watchForAthlete(String athleteId) {
    this.athleteId = athleteId;
    return Stream.value(const []);
  }
}
