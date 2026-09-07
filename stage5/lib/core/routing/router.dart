import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/web_workspace/pending_web_workspace_route.dart';
import 'package:stage5/core/web_workspace/web_workspace_location.dart';
import 'package:stage5/core/web_workspace/web_workspace_mode.dart';
import 'package:stage5/features/auth/presentation/app_entry_providers.dart';
import 'package:stage5/features/auth/presentation/home_screen.dart';
import 'package:stage5/features/auth/presentation/login_screen.dart';
import 'package:stage5/features/auth/presentation/onboarding_screen.dart';
import 'package:stage5/features/auth/presentation/web_workspace_shell.dart';
import 'package:stage5/features/exercises/presentation/exercise_detail_screen.dart';
import 'package:stage5/features/exercises/presentation/exercise_form_screen.dart';
import 'package:stage5/features/exercises/presentation/exercise_list_screen.dart';
import 'package:stage5/features/programs/presentation/athlete_schedule_screen.dart';
import 'package:stage5/features/programs/presentation/program_builder_screen.dart';
import 'package:stage5/features/programs/presentation/program_list_screen.dart';
import 'package:stage5/features/programs/presentation/roster_athletes_screen.dart';
import 'package:stage5/features/workouts/presentation/schedule_assignment_screen.dart';
import 'package:stage5/features/workouts/presentation/trainer_calendar_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_builder_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_completion_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_list_screen.dart';

/// App-level GoRouter configuration with auth and onboarding redirects.
///
/// Uses [appEntryStateProvider] as the single source of truth:
/// - signedOut → /login
/// - waitingForProfile → /loading
/// - needsOnboarding → /onboarding
/// - ready → the responsive authenticated entry point
/// - error → /error
final pendingWebWorkspaceRouteProvider =
    Provider<PendingWebWorkspaceRoute>((ref) {
  return PendingWebWorkspaceRoute(readInitialWebWorkspaceLocation());
});

final routerProvider = Provider<GoRouter>((ref) {
  final appState = ref.watch(appEntryStateProvider);
  final pendingWorkspaceRoute = ref.watch(pendingWebWorkspaceRouteProvider);

  final router = GoRouter(
    redirect: (context, state) {
      final loc = state.matchedLocation;

      switch (appState) {
        case AppEntryState.signedOut:
          pendingWorkspaceRoute.remember(state.uri.toString());
          return loc == '/login' ? null : '/login';
        case AppEntryState.waitingForProfile:
          return loc == '/loading' ? null : '/loading';
        case AppEntryState.needsOnboarding:
          return loc == '/onboarding' ? null : '/onboarding';
        case AppEntryState.ready:
          final pendingLocation = pendingWorkspaceRoute.take();
          if (pendingLocation != null &&
              WebWorkspaceMode.fromLocation(loc) == null) {
            return pendingLocation;
          }
          if (loc == '/login' || loc == '/onboarding' || loc == '/loading') {
            return '/';
          }
          return null;
        case AppEntryState.error:
          return loc == '/error' ? null : '/error';
      }
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ResponsiveAuthenticatedHome(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/exercises',
        builder: (context, state) => const ExerciseListScreen(),
      ),
      GoRoute(
        path: '/exercises/new',
        builder: (context, state) => const ExerciseFormScreen(),
      ),
      GoRoute(
        path: '/exercises/:id',
        builder: (context, state) => ExerciseDetailScreen(
          exerciseId: state.pathParameters['id']!,
          versionNumber: int.tryParse(
            state.uri.queryParameters['version'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/exercises/:id/edit',
        builder: (context, state) =>
            ExerciseFormScreen(exerciseId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/workouts',
        builder: (context, state) => const WorkoutListScreen(),
      ),
      GoRoute(
        path: '/workouts/new',
        builder: (context, state) => const WorkoutBuilderScreen(),
      ),
      GoRoute(
        path: '/workouts/:id',
        builder: (context, state) => WorkoutBuilderScreen(
          workoutId: state.pathParameters['id'],
          copyFromId: state.uri.queryParameters['copyFrom'],
        ),
      ),
      GoRoute(
        path: '/programs',
        builder: (context, state) => const ProgramListScreen(),
      ),
      GoRoute(
        path: '/roster',
        builder: (context, state) => const RosterAthletesScreen(),
      ),
      GoRoute(
        path: '/programs/new',
        builder: (context, state) => const ProgramBuilderScreen(),
      ),
      GoRoute(
        path: '/programs/:id',
        builder: (context, state) => ProgramBuilderScreen(
          programId: state.pathParameters['id'],
          copyFromId: state.uri.queryParameters['copyFrom'],
        ),
      ),
      GoRoute(
        path: '/assign',
        builder: (context, state) => ScheduleAssignmentScreen(
          programId: state.uri.queryParameters['programId'],
          preselectedAthleteId: state.uri.queryParameters['athleteId'],
          preselectedDate: DateTime.tryParse(
            state.uri.queryParameters['date'] ?? '',
          ),
          startInProgramMode: state.uri.queryParameters['mode'] == 'program',
          selfService: state.uri.queryParameters['selfService'] == 'true',
        ),
      ),
      GoRoute(
        path: '/programs/:id/athlete/:athleteId',
        builder: (context, state) => AthleteScheduleScreen(
          programId: state.pathParameters['id']!,
          athleteId: state.pathParameters['athleteId']!,
        ),
      ),
      GoRoute(
        path: '/schedule',
        builder: (context, state) =>
            const TrainerCalendarScreen(selfService: true),
      ),
      GoRoute(
        path: '/trainer-calendar',
        builder: (context, state) => TrainerCalendarScreen(
          athleteId: state.uri.queryParameters['athleteId'],
        ),
      ),
      GoRoute(
        path: '/workouts/complete/:instanceId',
        builder: (context, state) => WorkoutCompletionScreen(
          instanceId: state.pathParameters['instanceId']!,
        ),
      ),
      GoRoute(
        path: '/athlete/today',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.athlete,
          destination: WebWorkspaceDestination.athleteToday,
          webChild: HomeScreenContent(
            showTrainerTools: false,
            scheduleRoute: '/athlete/calendar',
          ),
        ),
      ),
      GoRoute(
        path: '/athlete/calendar',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.athlete,
          destination: WebWorkspaceDestination.athleteCalendar,
          webChild: TrainerCalendarScreen(selfService: true),
        ),
      ),
      GoRoute(
        path: '/athlete/programs',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.athlete,
          destination: WebWorkspaceDestination.athletePrograms,
          webChild: WebWorkspacePlaceholder(
            icon: Icons.school_outlined,
            title: 'My programs',
            description:
                'Your active programs are summarized on Today. A dedicated '
                'program workspace is coming next.',
          ),
        ),
      ),
      GoRoute(
        path: '/athlete/history',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.athlete,
          destination: WebWorkspaceDestination.athleteHistory,
          webChild: WebWorkspacePlaceholder(
            icon: Icons.history,
            title: 'Workout history',
            description:
                'Completed workouts and past training details will appear '
                'here.',
          ),
        ),
      ),
      GoRoute(
        path: '/athlete/progress',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.athlete,
          destination: WebWorkspaceDestination.athleteProgress,
          webChild: WebWorkspacePlaceholder(
            icon: Icons.insights,
            title: 'Progress',
            description:
                'Training trends, milestones, and progress insights are '
                'planned for a later Stage 5 slice.',
          ),
        ),
      ),
      GoRoute(
        path: '/athlete/messages',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.athlete,
          destination: WebWorkspaceDestination.athleteMessages,
          webChild: WebWorkspacePlaceholder(
            icon: Icons.chat_bubble_outline,
            title: 'Messages',
            description:
                'Trainer and athlete conversations will be available here.',
          ),
        ),
      ),
      GoRoute(
        path: '/trainer/dashboard',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.trainer,
          destination: WebWorkspaceDestination.trainerDashboard,
          webChild: WebWorkspacePlaceholder(
            icon: Icons.dashboard_outlined,
            title: 'Trainer dashboard',
            description: 'Client activity, upcoming assignments, and coaching '
                'priorities will be summarized here.',
          ),
        ),
      ),
      GoRoute(
        path: '/trainer/clients',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.trainer,
          destination: WebWorkspaceDestination.trainerClients,
          webChild: RosterAthletesScreen(),
        ),
      ),
      GoRoute(
        path: '/trainer/exercises',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.trainer,
          destination: WebWorkspaceDestination.trainerExercises,
          webChild: ExerciseListScreen(),
        ),
      ),
      GoRoute(
        path: '/trainer/workouts',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.trainer,
          destination: WebWorkspaceDestination.trainerWorkouts,
          webChild: WorkoutListScreen(),
        ),
      ),
      GoRoute(
        path: '/trainer/programs',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.trainer,
          destination: WebWorkspaceDestination.trainerPrograms,
          webChild: ProgramListScreen(),
        ),
      ),
      GoRoute(
        path: '/trainer/calendar',
        builder: (context, state) => const AdaptiveWebWorkspaceRoute(
          mode: WebWorkspaceMode.trainer,
          destination: WebWorkspaceDestination.trainerCalendar,
          webChild: TrainerCalendarScreen(),
        ),
      ),
      GoRoute(
        path: '/loading',
        builder: (context, state) => const _LoadingScreen(),
      ),
      GoRoute(
        path: '/error',
        builder: (context, state) => const _ErrorScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Shown while waiting for the Cloud Function to create the user doc.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Setting up your account...'),
          ],
        ),
      ),
    );
  }
}

/// Shown when something goes wrong during the entry flow.
class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Something went wrong. Please try again.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                // Sign out and restart the flow
              },
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}
