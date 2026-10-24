import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/athlete_dashboard/data/athlete_dashboard_repository.dart';
import 'package:stage5/features/athlete_dashboard/domain/athlete_activity_event.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';

final athleteDashboardRepositoryProvider =
    Provider<AthleteDashboardRepository>((ref) {
  return AthleteDashboardRepository();
});

final athleteDashboardProvider =
    FutureProvider.autoDispose<AthleteDashboardPage>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) {
    throw StateError('An authenticated athlete is required');
  }
  return ref
      .watch(athleteDashboardRepositoryProvider)
      .loadInitialPage(user.uid);
});
