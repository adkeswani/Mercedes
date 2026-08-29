import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/features/auth/domain/user_profile.dart';
import 'package:stage5/features/auth/presentation/app_entry_providers.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/programs/domain/program.dart';
import 'package:stage5/features/programs/presentation/enrollment_providers.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_relationship_providers.dart';

/// Top-level roster backed by durable trainer-client relationships.
///
/// Tapping an athlete opens their calendar. Athletes are added by username
/// search followed by picking one of the coach's assignable programs to enroll
/// them into. Ending a relationship removes the athlete from the active roster
/// without deleting their existing assigned content.
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

  /// Programs the coach owns that someone can be enrolled into. Always
  /// includes assignable programs; when [includePersonal] is true, personal
  /// (self-only) programs are added too.
  ///
  /// Awaits the programs stream's first value so callers never see an empty
  /// list merely because the stream has not loaded yet.
  Future<List<Program>> _enrollablePrograms(
      {bool includePersonal = false}) async {
    final programs = await ref.read(programsProvider.future);
    return programs
        .where((p) => p.isAssignable || (includePersonal && p.isPersonal))
        .toList();
  }

  /// Builds the enroll dialog's children, grouping programs under
  /// non-selectable folder headers (folders alphabetical, programs by name),
  /// with an "Ungrouped" section last when folders exist.
  List<Widget> _groupedEnrollOptions(BuildContext ctx, List<Program> programs) {
    final folders = ref.read(programFoldersProvider).valueOrNull ?? const [];
    final folderById = {for (final f in folders) f.id: f};
    final grouped = <String?, List<Program>>{};
    for (final p in programs) {
      final key = folderById.containsKey(p.folderId) ? p.folderId : null;
      grouped.putIfAbsent(key, () => []).add(p);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    final headerStyle = Theme.of(ctx).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(ctx).colorScheme.primary,
        );
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: Text(text, style: headerStyle),
        );
    SimpleDialogOption option(Program p) => SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(p),
          child: Text(p.name),
        );

    final sortedFolders = [...folders]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final items = <Widget>[];
    for (final folder in sortedFolders) {
      final progs = grouped[folder.id];
      if (progs == null || progs.isEmpty) continue;
      items.add(header(folder.name));
      items.addAll(progs.map(option));
    }

    final ungrouped = grouped[null] ?? const [];
    if (ungrouped.isNotEmpty) {
      if (items.isNotEmpty) items.add(header('Ungrouped'));
      items.addAll(ungrouped.map(option));
    }
    return items;
  }

  Future<void> _enrollAthlete(
    UserProfile profile, {
    bool includePersonal = false,
  }) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    final programs =
        await _enrollablePrograms(includePersonal: includePersonal);
    if (!mounted) return;
    if (programs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            includePersonal
                ? 'Create a program before adding yourself to the roster'
                : 'Create an assignable program before enrolling athletes',
          ),
        ),
      );
      return;
    }

    final program = await showDialog<Program>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Enroll ${profile.displayName} in...'),
        children: _groupedEnrollOptions(ctx, programs),
      ),
    );
    if (program == null) return;

    try {
      final relationshipRepo =
          ref.read(trainerClientRelationshipRepositoryProvider);
      if (!await relationshipRepo.isActive(uid, profile.uid)) {
        await relationshipRepo.startRelationship(
          trainerId: uid,
          athleteId: profile.uid,
          callerUserId: uid,
        );
      }
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
  ) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End trainer-client relationship?'),
        content: Text(
          '$displayName will leave your active roster and no new work can be '
          'assigned. Existing assigned content remains available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End relationship'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(trainerClientRelationshipRepositoryProvider)
          .endRelationship(
            trainerId: uid,
            athleteId: athleteId,
            callerUserId: uid,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Relationship with $displayName ended')),
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
    final relationshipsAsync = ref.watch(trainerClientsProvider);

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

          const SizedBox(height: 8),
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
                        backgroundImage: NetworkImage(_searchResult!.photoUrl!),
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

          relationshipsAsync.when(
            data: (relationships) {
              final athleteIds = {
                for (final relationship in relationships) relationship.athleteId
              }.toList();
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
                        _removeAthlete(athleteId, displayName),
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
    final isSelf = ref.watch(authStateProvider).value?.uid == athleteId;

    return FutureBuilder(
      future: profileRepo.getUserProfile(athleteId),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final baseName = profile?.displayName ?? athleteId;
        final displayName = isSelf ? '$baseName (You)' : baseName;
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
