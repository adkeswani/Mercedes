import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

enum WorkoutDeleteStatus {
  deleted,
  cancelled,
  blocked,
  failed,
  alreadyPending,
}

class WorkoutDeleteResult {
  const WorkoutDeleteResult(this.status, {this.error});

  final WorkoutDeleteStatus status;
  final Object? error;

  bool get deleted => status == WorkoutDeleteStatus.deleted;
}

final workoutDeleteControllerProvider =
    StateNotifierProvider<WorkoutDeleteController, Set<String>>((ref) {
  return WorkoutDeleteController(ref);
});

class WorkoutDeleteController extends StateNotifier<Set<String>> {
  WorkoutDeleteController(this._ref) : super(const {});

  final Ref _ref;

  Future<WorkoutDeleteResult> delete({
    required String workoutId,
    required String userId,
  }) async {
    if (state.contains(workoutId)) {
      return const WorkoutDeleteResult(WorkoutDeleteStatus.alreadyPending);
    }

    state = {...state, workoutId};
    try {
      final repository = _ref.read(workoutTemplateRepositoryProvider);
      if (await repository.isWorkoutReferenced(workoutId)) {
        return const WorkoutDeleteResult(WorkoutDeleteStatus.blocked);
      }
      await repository.softDelete(workoutId, userId);
      return const WorkoutDeleteResult(WorkoutDeleteStatus.deleted);
    } catch (error) {
      return WorkoutDeleteResult(WorkoutDeleteStatus.failed, error: error);
    } finally {
      state = {...state}..remove(workoutId);
    }
  }
}

Future<WorkoutDeleteResult> confirmAndDeleteWorkout({
  required BuildContext context,
  required WidgetRef ref,
  required String workoutId,
  required String workoutName,
}) async {
  if (ref.read(workoutDeleteControllerProvider).contains(workoutId)) {
    return const WorkoutDeleteResult(WorkoutDeleteStatus.alreadyPending);
  }
  final userFuture = ref.read(authStateProvider.future);
  final controller = ref.read(workoutDeleteControllerProvider.notifier);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete workout template?'),
      content: Text(
        'Are you sure you want to delete "$workoutName"? '
        'This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    return const WorkoutDeleteResult(WorkoutDeleteStatus.cancelled);
  }

  final user = await userFuture;
  if (user == null) {
    final result = WorkoutDeleteResult(
      WorkoutDeleteStatus.failed,
      error: StateError('Sign in is required to delete a workout'),
    );
    if (context.mounted) {
      _showDeleteError(context, workoutName, result);
    }
    return result;
  }

  final result = await controller.delete(
    workoutId: workoutId,
    userId: user.uid,
  );
  if (!context.mounted) {
    return result;
  }

  switch (result.status) {
    case WorkoutDeleteStatus.blocked:
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot delete - this workout is used in a program.',
          ),
        ),
      );
      break;
    case WorkoutDeleteStatus.failed:
      _showDeleteError(context, workoutName, result);
      break;
    case WorkoutDeleteStatus.deleted:
    case WorkoutDeleteStatus.cancelled:
    case WorkoutDeleteStatus.alreadyPending:
      break;
  }
  return result;
}

void _showDeleteError(
  BuildContext context,
  String workoutName,
  WorkoutDeleteResult result,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Could not delete $workoutName. Check your connection and permissions, '
        'then try again. ${result.error}',
      ),
    ),
  );
}
