import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/exercises/data/exercise_template_repository.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';

void main() {
  test('owner-scoped provider invokes backfill with the requested user', () async {
    final repository = _RecordingExerciseRepository();
    final container = ProviderContainer(
      overrides: [
        exerciseTemplateRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final count = await container.read(
      exerciseVersionBackfillForUserProvider('owner1').future,
    );

    expect(count, 2);
    expect(repository.backfilledUserId, 'owner1');
  });
}

class _RecordingExerciseRepository extends ExerciseTemplateRepository {
  _RecordingExerciseRepository()
      : super(firestore: FakeFirebaseFirestore());

  String? backfilledUserId;

  @override
  Future<int> backfillOwnedLegacyExercises(String userId) async {
    backfilledUserId = userId;
    return 2;
  }
}
