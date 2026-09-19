import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/trainer_dashboard/data/trainer_dashboard_repository.dart';
import 'package:stage5/features/trainer_dashboard/domain/trainer_activity_event.dart';

final trainerDashboardRepositoryProvider = Provider<TrainerDashboardRepository>(
  (ref) {
    return TrainerDashboardRepository();
  },
);

final trainerDashboardProvider =
    FutureProvider.autoDispose<TrainerDashboardPage>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) {
    throw StateError('An authenticated trainer is required');
  }
  return ref
      .watch(trainerDashboardRepositoryProvider)
      .loadInitialPage(user.uid);
});
