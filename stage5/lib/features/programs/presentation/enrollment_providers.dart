import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/programs/data/enrollment_repository.dart';
import 'package:stage5/features/programs/domain/enrollment.dart';
import 'package:stage5/features/programs/domain/program.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';

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

/// Streams all athletes enrolled across the current user's owned programs.
///
/// Powers the trainer's athlete picker for the per-athlete calendar.
final ownerEnrollmentsProvider = StreamProvider<List<Enrollment>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(enrollmentRepositoryProvider);
  return repo.watchEnrollmentsByOwner(user.uid);
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

/// Combines enrolled programs with personal programs owned by the athlete.
List<Program> athleteAccessiblePrograms({
  required Iterable<Program> enrolledPrograms,
  required Iterable<Program> ownedPrograms,
}) {
  final byId = <String, Program>{
    for (final program in enrolledPrograms) program.id: program,
    for (final program in ownedPrograms)
      if (program.isPersonal) program.id: program,
  };
  return byId.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Resolves active enrollments and owned personal programs for self-service.
final myEnrolledProgramsProvider = FutureProvider<List<Program>>((ref) async {
  final enrollments = await ref.watch(myEnrollmentsProvider.future);
  final repo = ref.watch(programRepositoryProvider);
  final enrolledPrograms = await Future.wait(
    enrollments.map((enrollment) => repo.getById(enrollment.programId)),
  );
  final ownedPrograms = await ref.watch(programsProvider.future);
  return athleteAccessiblePrograms(
    enrolledPrograms: enrolledPrograms.whereType<Program>(),
    ownedPrograms: ownedPrograms,
  );
});
