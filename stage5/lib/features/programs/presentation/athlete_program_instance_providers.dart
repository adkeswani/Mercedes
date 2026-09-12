import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/programs/data/athlete_program_instance_repository.dart';
import 'package:stage5/features/programs/domain/athlete_program_instance.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_relationship_providers.dart';

final athleteProgramInstanceRepositoryProvider =
    Provider<AthleteProgramInstanceRepository>((ref) {
  return AthleteProgramInstanceRepository();
});

final myAthleteProgramInstancesProvider =
    StreamProvider<List<AthleteProgramInstance>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return const Stream.empty();
  }
  final repository = ref.watch(athleteProgramInstanceRepositoryProvider);
  ref.watch(myAthleteProgramInstanceBackfillStatusProvider);
  return repository.watchForAthlete(user.uid);
});

final myAthleteProgramInstanceBackfillStatusProvider =
    Provider<AsyncValue<int>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return const AsyncData(0);
  }
  return ref.watch(athleteProgramInstanceBackfillProvider(user.uid));
});

final managedAthleteProgramInstancesProvider =
    StreamProvider<List<AthleteProgramInstance>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return const Stream.empty();
  }
  final relationships = ref.watch(trainerClientsProvider).valueOrNull;
  if (relationships == null) {
    return const Stream.empty();
  }
  return ref.watch(athleteProgramInstanceRepositoryProvider).watchForTrainer(
        user.uid,
        relationships.map((relationship) => relationship.athleteId),
      );
});

final athleteProgramInstanceBackfillProvider =
    FutureProvider.family<int, String>((ref, athleteId) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return Future.value(0);
  }
  return ref
      .watch(athleteProgramInstanceRepositoryProvider)
      .backfillLegacyAssignments(athleteId: athleteId, actorId: user.uid);
});
