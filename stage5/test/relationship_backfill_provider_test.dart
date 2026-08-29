import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/relationships/data/trainer_client_relationship_repository.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_relationship_providers.dart';

void main() {
  test('owner-scoped provider invokes backfill with the requested trainer',
      () async {
    final repository = _RecordingRelationshipRepository();
    final container = ProviderContainer(
      overrides: [
        trainerClientRelationshipRepositoryProvider.overrideWithValue(
          repository,
        ),
      ],
    );
    addTearDown(container.dispose);

    final count = await container.read(
      trainerClientRelationshipBackfillForUserProvider('trainer1').future,
    );

    expect(count, 2);
    expect(repository.trainerId, 'trainer1');
    expect(repository.callerUserId, 'trainer1');
  });
}

class _RecordingRelationshipRepository
    extends TrainerClientRelationshipRepository {
  _RecordingRelationshipRepository()
      : super(firestore: FakeFirebaseFirestore());

  String? trainerId;
  String? callerUserId;

  @override
  Future<int> backfillActiveEnrollmentRelationships({
    required String trainerId,
    required String callerUserId,
  }) async {
    this.trainerId = trainerId;
    this.callerUserId = callerUserId;
    return 2;
  }
}
