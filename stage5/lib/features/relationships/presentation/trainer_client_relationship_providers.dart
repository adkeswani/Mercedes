import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/auth/presentation/app_entry_providers.dart';
import 'package:stage5/features/relationships/data/trainer_client_relationship_repository.dart';
import 'package:stage5/features/relationships/domain/trainer_client_relationship.dart';

final trainerClientRelationshipRepositoryProvider =
    Provider<TrainerClientRelationshipRepository>((ref) {
  return TrainerClientRelationshipRepository();
});

/// Idempotently materializes durable roster relationships for active legacy
/// enrollments owned by [trainerId].
final trainerClientRelationshipBackfillForUserProvider =
    FutureProvider.family<int, String>((ref, trainerId) async {
  final repo = ref.watch(trainerClientRelationshipRepositoryProvider);
  final backfilled = await repo.backfillActiveEnrollmentRelationships(
    trainerId: trainerId,
    callerUserId: trainerId,
  );
  final recovered = await repo.recoverEndingRelationships(
    trainerId: trainerId,
    callerUserId: trainerId,
  );
  return backfilled + recovered;
});

final trainerClientsProvider = StreamProvider<List<TrainerClientRelationship>>((
  ref,
) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final backfill = ref.watch(
    trainerClientRelationshipBackfillForUserProvider(user.uid).future,
  );
  final repository = ref.watch(trainerClientRelationshipRepositoryProvider);
  return Stream.fromFuture(
    backfill,
  ).asyncExpand((_) => repository.watchClients(user.uid));
});

final athleteTrainersProvider = StreamProvider<List<TrainerClientRelationship>>(
  (ref) {
    final user = ref.watch(authStateProvider).value;
    if (user == null) return const Stream.empty();
    return ref
        .watch(trainerClientRelationshipRepositoryProvider)
        .watchTrainers(user.uid);
  },
);

final activeTrainerClientNamesProvider = FutureProvider<Map<String, String>>((
  ref,
) async {
  final clients = await ref.watch(trainerClientsProvider.future);
  final profiles = ref.watch(userProfileRepositoryProvider);
  final names = <String, String>{};
  for (final client in clients) {
    final profile = await profiles.getUserProfile(client.athleteId);
    final displayName = profile?.displayName.trim();
    names[client.athleteId] = displayName == null || displayName.isEmpty
        ? client.athleteId
        : displayName;
  }
  return names;
});
