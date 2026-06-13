import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage3/features/auth/presentation/auth_providers.dart';
import 'package:stage3/features/programs/data/enrollment_repository.dart';
import 'package:stage3/features/programs/domain/enrollment.dart';

/// Singleton repository for enrollments.
final enrollmentRepositoryProvider = Provider<EnrollmentRepository>((ref) {
  return EnrollmentRepository();
});

/// Streams all active enrollments for a specific program (owner's roster view).
///
/// Use with `ref.watch(programEnrollmentsProvider('programId'))`.
/// Requires the current user to be the program owner (addedBy filter).
final programEnrollmentsProvider =
    StreamProvider.family<List<Enrollment>, String>((ref, programId) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(enrollmentRepositoryProvider);
  return repo.watchEnrollments(programId, ownerId: user.uid);
});

/// Streams all programs the current user is enrolled in as an athlete.
///
/// Used on the home screen to show "Enrolled Programs" section.
final myEnrollmentsProvider = StreamProvider<List<Enrollment>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(enrollmentRepositoryProvider);
  return repo.watchMyEnrollments(user.uid);
});
