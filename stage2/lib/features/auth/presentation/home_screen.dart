import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage2/features/auth/presentation/auth_providers.dart';

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
