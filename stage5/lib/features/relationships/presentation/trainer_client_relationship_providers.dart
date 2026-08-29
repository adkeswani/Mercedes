import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/relationships/data/trainer_client_relationship_repository.dart';
import 'package:stage5/features/relationships/domain/trainer_client_relationship.dart';

final trainerClientRelationshipRepositoryProvider =
    Provider<TrainerClientRelationshipRepository>((ref) {
  return TrainerClientRelationshipRepository();
});

final trainerClientsProvider =
    StreamProvider<List<TrainerClientRelationship>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref
      .watch(trainerClientRelationshipRepositoryProvider)
      .watchClients(user.uid);
});

final athleteTrainersProvider =
    StreamProvider<List<TrainerClientRelationship>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref
      .watch(trainerClientRelationshipRepositoryProvider)
      .watchTrainers(user.uid);
});
