import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage3/features/auth/presentation/auth_providers.dart';
import 'package:stage3/features/programs/presentation/enrollment_providers.dart';

/// Home screen shown after authentication and onboarding.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mercedes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () {
              ref.read(authRepositoryProvider).signOut();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User greeting
          authState.when(
            data: (user) => Row(
              children: [
                if (user?.photoURL != null)
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(user!.photoURL!),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, ${user?.displayName ?? 'User'}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        user?.email ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
          ),
          const SizedBox(height: 24),
          // Feature navigation cards
          _FeatureCard(
            icon: Icons.fitness_center,
            title: 'Exercise Library',
            subtitle: 'Create and manage exercise templates',
            onTap: () => context.push('/exercises'),
          ),
          _FeatureCard(
            icon: Icons.sports_gymnastics,
            title: 'Workout Templates',
            subtitle: 'Build and publish workout templates',
            onTap: () => context.push('/workouts'),
          ),
          _FeatureCard(
            icon: Icons.folder_outlined,
            title: 'Programs',
            subtitle: 'Create programs and assign workouts',
            onTap: () => context.push('/programs'),
          ),
          const SizedBox(height: 24),
          // Enrolled programs section
          _EnrolledProgramsSection(),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Shows programs the current user is enrolled in as an athlete.
class _EnrolledProgramsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enrollmentsAsync = ref.watch(myEnrollmentsProvider);

    return enrollmentsAsync.when(
      data: (enrollments) {
        if (enrollments.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enrolled Programs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...enrollments.map((enrollment) {
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.school, size: 32),
                  title: Text('Program'),
                  subtitle: Text(
                    'Enrolled ${_formatDate(enrollment.addedAt)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    '/programs/${enrollment.programId}',
                  ),
                ),
              );
            }),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  String _formatDate(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return '';
    return '${date.month}/${date.day}/${date.year}';
  }
}
