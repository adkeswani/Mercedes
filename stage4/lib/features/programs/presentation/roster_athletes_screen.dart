import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage4/features/auth/domain/user_profile.dart';
import 'package:stage4/features/auth/presentation/app_entry_providers.dart';
import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/programs/domain/enrollment.dart';
import 'package:stage4/features/programs/domain/program.dart';
import 'package:stage4/features/programs/presentation/enrollment_providers.dart';
import 'package:stage4/features/programs/presentation/program_providers.dart';

/// Top-level roster: a flat list of every athlete enrolled across the coach's
/// programs.
///
/// Tapping an athlete opens their calendar. Athletes are added by username
/// search followed by picking one of the coach's assignable programs to enroll
/// them into, and removed (from every owned program) via the trailing button.
class RosterAthletesScreen extends ConsumerStatefulWidget {
  const RosterAthletesScreen({super.key});

  @override
  ConsumerState<RosterAthletesScreen> createState() =>
      _RosterAthletesScreenState();
}

class _RosterAthletesScreenState extends ConsumerState<RosterAthletesScreen> {
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
      final profile =
          await ref.read(userProfileRepositoryProvider).getUserByUsername(
                username,
              );
      if (!mounted) return;

      if (profile == null) {
        setState(() {
          _searchError = 'No user found with username "$username"';
          _isSearching = false;
        });
        return;
      }

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

  /// Programs the coach owns that athletes can be enrolled into.
  List<Program> _assignablePrograms() {
    final programs = ref.read(programsProvider).valueOrNull ?? const [];
    return programs.where((p) => p.isAssignable).toList();
  }

  Future<void> _enrollAthlete(UserProfile profile) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    final programs = _assignablePrograms();
    if (programs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Create an assignable program before enrolling athletes',
          ),
        ),
      );
      return;
    }

    final program = await showDialog<Program>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Enroll ${profile.displayName} in...'),
        children: [
          for (final p in programs)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p),
              child: Text(p.name),
            ),
        ],
      ),
    );
    if (program == null) return;

    try {
      await ref.read(enrollmentRepositoryProvider).enrollAthlete(
            programId: program.id,
            athleteId: profile.uid,
            addedBy: uid,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${profile.displayName} enrolled in ${program.name}'),
          ),
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

  Future<void> _removeAthlete(
    String athleteId,
    String displayName,
    List<Enrollment> enrollments,
  ) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    final programNames = {
      for (final p in ref.read(programsProvider).valueOrNull ?? const [])
        p.id: p.name,
    };
    final enrolledProgramIds = enrollments
        .where((e) => e.athleteId == athleteId)
        .map((e) => e.programId)
        .toSet()
        .toList();
    if (enrolledProgramIds.isEmpty) return;

    // Step 1: choose which program (or all) to remove from.
    const allSentinel = '__all__';
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Remove $displayName from...'),
        children: [
          for (final pid in enrolledProgramIds)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(pid),
              child: Text(programNames[pid] ?? pid),
            ),
          if (enrolledProgramIds.length > 1)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(allSentinel),
              child: const Text('All programs'),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    final removeAll = choice == allSentinel;
    final targetIds = removeAll ? enrolledProgramIds : [choice];
    final targetLabel =
        removeAll ? 'all of your programs' : (programNames[choice] ?? choice);

    // Step 2: confirm the (destructive) removal.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove athlete?'),
        content: Text(
          'Remove $displayName from $targetLabel? Their future scheduled '
          'workouts in ${removeAll ? 'those programs' : 'that program'} will '
          'be cancelled.',
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

    try {
      final repo = ref.read(enrollmentRepositoryProvider);
      for (final programId in targetIds) {
        await repo.removeAthlete(
          programId: programId,
          athleteId: athleteId,
          removedBy: uid,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$displayName removed from $targetLabel'),
          ),
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
    final enrollmentsAsync = ref.watch(ownerEnrollmentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Roster')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Add athlete by username
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
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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

          Text(
            'Athletes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),

          enrollmentsAsync.when(
            data: (enrollments) {
              final athleteIds =
                  {for (final e in enrollments) e.athleteId}.toList();
              if (athleteIds.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('No athletes on your roster yet')),
                );
              }
              return Column(
                children: athleteIds.map((athleteId) {
                  return _AthleteRow(
                    athleteId: athleteId,
                    onOpen: () =>
                        context.push('/trainer-calendar?athleteId=$athleteId'),
                    onRemove: (displayName) =>
                        _removeAthlete(athleteId, displayName, enrollments),
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

/// Roster row for a single athlete, resolving their profile asynchronously.
class _AthleteRow extends ConsumerWidget {
  const _AthleteRow({
    required this.athleteId,
    required this.onOpen,
    required this.onRemove,
  });

  final String athleteId;
  final VoidCallback onOpen;
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
            onTap: onOpen,
            leading: profile?.photoUrl != null
                ? CircleAvatar(
                    backgroundImage: NetworkImage(profile!.photoUrl!),
                  )
                : const CircleAvatar(child: Icon(Icons.person)),
            title: Text(displayName),
            subtitle: username != null ? Text('@$username') : null,
            trailing: IconButton(
              icon: const Icon(Icons.person_remove),
              tooltip: 'Remove athlete',
              onPressed: () => onRemove(displayName),
            ),
          ),
        );
      },
    );
  }
}
