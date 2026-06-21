import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage4/features/auth/domain/user_profile.dart';
import 'package:stage4/features/auth/presentation/app_entry_providers.dart';
import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/programs/presentation/enrollment_providers.dart';

/// Roster management screen for program owners.
///
/// Shows currently enrolled athletes and allows adding/removing athletes
/// via exact username search.
class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key, required this.programId});

  final String programId;

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  final _usernameController = TextEditingController();
  bool _isSearching = false;
  String? _searchError;
  UserProfile? _searchResult;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
      _searchResult = null;
    });

    try {
      final profileRepo = ref.read(userProfileRepositoryProvider);
      final profile = await profileRepo.getUserByUsername(username);

      if (!mounted) return;

      if (profile == null) {
        setState(() {
          _searchError = 'No user found with username "$username"';
          _isSearching = false;
        });
        return;
      }

      // Check if already enrolled
      final enrollmentRepo = ref.read(enrollmentRepositoryProvider);
      final enrolled = await enrollmentRepo.isEnrolled(
        widget.programId,
        profile.uid,
      );

      if (!mounted) return;

      if (enrolled) {
        setState(() {
          _searchError = '${profile.displayName} is already enrolled';
          _isSearching = false;
        });
        return;
      }

      // Check if searching for self
      final currentUid = ref.read(authStateProvider).value?.uid;
      if (profile.uid == currentUid) {
        setState(() {
          _searchError = 'You cannot enroll yourself';
          _isSearching = false;
        });
        return;
      }

      setState(() {
        _searchResult = profile;
        _isSearching = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = 'Search failed: $e';
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _enrollAthlete(UserProfile profile) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    try {
      final repo = ref.read(enrollmentRepositoryProvider);
      await repo.enrollAthlete(
        programId: widget.programId,
        athleteId: profile.uid,
        addedBy: uid,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${profile.displayName} enrolled')),
        );
        setState(() {
          _searchResult = null;
          _usernameController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to enroll: $e')),
        );
      }
    }
  }

  Future<void> _removeAthlete(String athleteId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove athlete?'),
        content: Text(
          'Remove $displayName from this program? '
          'Their future scheduled workouts will be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    try {
      final repo = ref.read(enrollmentRepositoryProvider);
      await repo.removeAthlete(
        programId: widget.programId,
        athleteId: athleteId,
        removedBy: uid,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$displayName removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrollmentsAsync =
        ref.watch(programEnrollmentsProvider(widget.programId));

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Roster')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search section
          Text(
            'Add Athlete',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'Enter exact username',
                    prefixIcon: Icon(Icons.search),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchUser(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isSearching ? null : _searchUser,
                child: _isSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Search'),
              ),
            ],
          ),

          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _searchError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),

          if (_searchResult != null)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                leading: _searchResult!.photoUrl != null
                    ? CircleAvatar(
                        backgroundImage:
                            NetworkImage(_searchResult!.photoUrl!),
                      )
                    : const CircleAvatar(child: Icon(Icons.person)),
                title: Text(_searchResult!.displayName),
                subtitle: Text('@${_searchResult!.username ?? ''}'),
                trailing: FilledButton(
                  onPressed: () => _enrollAthlete(_searchResult!),
                  child: const Text('Enroll'),
                ),
              ),
            ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // Current roster
          Text(
            'Current Roster',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),

          enrollmentsAsync.when(
            data: (enrollments) {
              if (enrollments.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text('No athletes enrolled yet'),
                  ),
                );
              }
              return Column(
                children: enrollments.map((enrollment) {
                  return _AthleteCard(
                    programId: widget.programId,
                    athleteId: enrollment.athleteId,
                    addedAt: enrollment.addedAt,
                    onRemove: (displayName) => _removeAthlete(
                      enrollment.athleteId,
                      displayName,
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}

/// Card showing an enrolled athlete with their profile info.
///
/// Loads the user profile asynchronously to display name and photo.
class _AthleteCard extends ConsumerWidget {
  const _AthleteCard({
    required this.programId,
    required this.athleteId,
    required this.addedAt,
    required this.onRemove,
  });

  final String programId;
  final String athleteId;
  final DateTime addedAt;
  final void Function(String displayName) onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileRepo = ref.watch(userProfileRepositoryProvider);

    return FutureBuilder(
      future: profileRepo.getUserProfile(athleteId),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final displayName = profile?.displayName ?? athleteId;
        final username = profile?.username;

        return Card(
          child: ListTile(
            leading: profile?.photoUrl != null
                ? CircleAvatar(
                    backgroundImage: NetworkImage(profile!.photoUrl!),
                  )
                : const CircleAvatar(child: Icon(Icons.person)),
            title: Text(displayName),
            subtitle: Text(
              username != null ? '@$username' : 'Enrolled ${_formatDate(addedAt)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.assignment_add),
                  tooltip: 'Assign workout or program',
                  onPressed: () => context.push(
                    '/programs/$programId/assign?athleteId=$athleteId',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.person_remove),
                  tooltip: 'Remove athlete',
                  onPressed: () => onRemove(displayName),
                ),
              ],
            ),
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
