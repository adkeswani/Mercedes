import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/relationships/data/trainer_client_relationship_repository.dart';
import 'package:stage5/features/relationships/domain/trainer_client_relationship.dart';

final trainerClientRelationshipRepositoryProvider =
    Provider<TrainerClientRelationshipRepository>((ref) {
  return TrainerClientRelationshipRepository();
});

/// Idempotently materializes durable roster relationships for active legacy
/// enrollments owned by [trainerId].
final trainerClientRelationshipBackfillForUserProvider =
    FutureProvider.family<int, String>((ref, trainerId) {
  final repo = ref.watch(trainerClientRelationshipRepositoryProvider);
  return repo.backfillActiveEnrollmentRelationships(
    trainerId: trainerId,
    callerUserId: trainerId,
  );
});

final trainerClientsProvider =
    StreamProvider<List<TrainerClientRelationship>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final backfill = ref
      .watch(trainerClientRelationshipBackfillForUserProvider(user.uid).future);
  final repository = ref.watch(trainerClientRelationshipRepositoryProvider);
  return Stream.fromFuture(backfill).asyncExpand(
    (_) => repository.watchClients(user.uid),
  );
});

final athleteTrainersProvider =
    StreamProvider<List<TrainerClientRelationship>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref
      .watch(trainerClientRelationshipRepositoryProvider)
      .watchTrainers(user.uid);
});
