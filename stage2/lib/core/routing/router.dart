import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage2/features/auth/presentation/app_entry_providers.dart';
import 'package:stage2/features/auth/presentation/home_screen.dart';
import 'package:stage2/features/auth/presentation/login_screen.dart';
import 'package:stage2/features/auth/presentation/onboarding_screen.dart';
import 'package:stage2/features/exercises/presentation/exercise_form_screen.dart';
import 'package:stage2/features/exercises/presentation/exercise_list_screen.dart';

/// App-level GoRouter configuration with auth and onboarding redirects.
///
/// Uses [appEntryStateProvider] as the single source of truth:
/// - signedOut → /login
/// - waitingForProfile → /loading
/// - needsOnboarding → /onboarding
/// - ready → /
/// - error → /error
final routerProvider = Provider<GoRouter>((ref) {
  final appState = ref.watch(appEntryStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final loc = state.matchedLocation;

      switch (appState) {
        case AppEntryState.signedOut:
          return loc == '/login' ? null : '/login';
        case AppEntryState.waitingForProfile:
          return loc == '/loading' ? null : '/loading';
        case AppEntryState.needsOnboarding:
          return loc == '/onboarding' ? null : '/onboarding';
        case AppEntryState.ready:
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
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
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
        builder: (context, state) => ExerciseFormScreen(
          exerciseId: state.pathParameters['id'],
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
