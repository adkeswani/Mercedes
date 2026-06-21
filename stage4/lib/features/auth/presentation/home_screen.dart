import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/programs/domain/enrollment.dart';
import 'package:stage4/features/programs/presentation/enrollment_providers.dart';
import 'package:stage4/features/programs/presentation/program_providers.dart';

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

          // ── My Training section ──
          Text(
            'My Training',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _FeatureCard(
            icon: Icons.calendar_month,
            title: 'My Schedule',
            subtitle: 'View your workout calendar',
            onTap: () => context.push('/schedule'),
          ),
          const SizedBox(height: 4),
          _EnrolledProgramsSection(),

          const SizedBox(height: 32),

          // ── Trainer Tools section ──
          Text(
            'Trainer Tools',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
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
          _FeatureCard(
            icon: Icons.calendar_month,
            title: 'Athlete Calendar',
            subtitle: "View and schedule an athlete's workouts",
            onTap: () => context.push('/trainer-calendar'),
          ),
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
          children: enrollments.map((enrollment) {
            return _EnrolledProgramCard(enrollment: enrollment);
          }).toList(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Card for a single enrolled program. Fetches the program name.
class _EnrolledProgramCard extends ConsumerWidget {
  const _EnrolledProgramCard({required this.enrollment});

  final Enrollment enrollment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programRepo = ref.watch(programRepositoryProvider);

    return FutureBuilder(
      future: programRepo.getById(enrollment.programId),
      builder: (context, snapshot) {
        final program = snapshot.data;

        // Hide card if program was deleted
        if (snapshot.connectionState == ConnectionState.done &&
            program == null) {
          return const SizedBox.shrink();
        }

        final name = program?.name ?? 'Loading...';
        final description = program?.description;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.school, size: 32),
            title: Text(name),
            subtitle: Text(
              description ?? 'Enrolled ${_formatDate(enrollment.addedAt)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              final uid = ref.read(authStateProvider).value?.uid;
              if (uid != null) {
                context.push(
                  '/programs/${enrollment.programId}/athlete/$uid',
                );
              }
            },
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return '';
    return '${date.month}/${date.day}/${date.year}';
  }
}
