import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/browser_smoke_status.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/trainer_dashboard/domain/trainer_activity_event.dart';
import 'package:stage5/features/trainer_dashboard/presentation/trainer_dashboard_providers.dart';

typedef QuickCommentCallback = Future<void> Function(
  CompletionActivityEvent event,
  String body,
);
typedef ReactionCallback = Future<void> Function(
  CompletionActivityEvent event,
  String reactionId,
);

class TrainerDashboardScreen extends ConsumerStatefulWidget {
  const TrainerDashboardScreen({
    this.onQuickComment,
    this.onReaction,
    super.key,
  });

  final QuickCommentCallback? onQuickComment;
  final ReactionCallback? onReaction;

  @override
  ConsumerState<TrainerDashboardScreen> createState() =>
      _TrainerDashboardScreenState();
}

class _TrainerDashboardScreenState
    extends ConsumerState<TrainerDashboardScreen> {
  TrainerActivityFilter _filter = TrainerActivityFilter.all;

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(trainerDashboardProvider);
    return Semantics(
      container: true,
      label: 'Trainer dashboard activity feed',
      child: dashboard.when(
        loading: () => Center(
          child: Semantics(
            label: 'Loading trainer activity',
            child: const CircularProgressIndicator(),
          ),
        ),
        error: (error, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            markBrowserSmokeSurfaceFailure('trainer-dashboard', 'error');
          });
          return _DashboardError(
            error: error,
            onRetry: () => ref.invalidate(trainerDashboardProvider),
          );
        },
        data: (page) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            markBrowserSmokeSurfaceReady(
              'trainer-dashboard',
              content: trainerDashboardCanaryContentFor(page.events),
            );
          });
          final events = filterTrainerActivityEvents(page.events, _filter);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(trainerDashboardProvider);
              await ref.read(trainerDashboardProvider.future);
            },
            child: CustomScrollView(
              key: const Key('trainer-dashboard-feed'),
              slivers: [
                SliverToBoxAdapter(
                  child: _DashboardHeader(
                    selected: _filter,
                    onSelected: (filter) => setState(() => _filter = filter),
                  ),
                ),
                if (events.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _DashboardEmpty(filter: _filter),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList.separated(
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 980),
                          child: _ActivityCard(
                            event: events[index],
                            onQuickComment: _quickComment,
                            onReaction: _reaction,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (page.isBounded)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Center(child: Text('Showing the newest activity')),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _quickComment(CompletionActivityEvent event, String body) async {
    if (widget.onQuickComment != null) {
      await widget.onQuickComment!(event, body);
      return;
    }
    final trainerId = ref.read(authStateProvider).valueOrNull?.uid;
    if (trainerId == null) {
      throw StateError('An authenticated trainer is required');
    }
    await ref.read(trainerDashboardRepositoryProvider).addQuickComment(
          trainerId: trainerId,
          workoutInstanceId: event.workoutInstanceId,
          body: body,
        );
    ref.invalidate(trainerDashboardProvider);
  }

  Future<void> _reaction(
    CompletionActivityEvent event,
    String reactionId,
  ) async {
    if (widget.onReaction != null) {
      await widget.onReaction!(event, reactionId);
      return;
    }
    final trainerId = ref.read(authStateProvider).valueOrNull?.uid;
    if (trainerId == null) {
      throw StateError('An authenticated trainer is required');
    }
    await ref.read(trainerDashboardRepositoryProvider).toggleReaction(
          trainerId: trainerId,
          workoutInstanceId: event.workoutInstanceId,
          reactionId: reactionId,
        );
    ref.invalidate(trainerDashboardProvider);
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.selected, required this.onSelected});

  final TrainerActivityFilter selected;
  final ValueChanged<TrainerActivityFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1012),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trainer dashboard',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Client completions, coaching conversations, and programs '
                'needing attention.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 18),
              Semantics(
                container: true,
                label: 'Activity filters',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in TrainerActivityFilter.values)
                      _FilterControl(
                        filter: filter,
                        selected: selected == filter,
                        onSelected: onSelected,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterControl extends StatelessWidget {
  const _FilterControl({
    required this.filter,
    required this.selected,
    required this.onSelected,
  });

  final TrainerActivityFilter filter;
  final bool selected;
  final ValueChanged<TrainerActivityFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final disabled = filter == TrainerActivityFilter.personalBests;
    final label = switch (filter) {
      TrainerActivityFilter.all => 'All',
      TrainerActivityFilter.completions => 'Completions',
      TrainerActivityFilter.comments => 'Comments',
      TrainerActivityFilter.reactions => 'Reactions',
      TrainerActivityFilter.programs => 'Programs',
      TrainerActivityFilter.personalBests => 'Personal bests — Coming later',
    };
    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: '$label filter',
      child: FilterChip(
        key: Key('trainer-dashboard-filter-${filter.name}'),
        label: Text(label),
        selected: selected,
        onSelected: disabled ? null : (_) => onSelected(filter),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.event,
    required this.onQuickComment,
    required this.onReaction,
  });

  final TrainerActivityEvent event;
  final QuickCommentCallback onQuickComment;
  final ReactionCallback onReaction;

  @override
  Widget build(BuildContext context) {
    if (event is CompletionActivityEvent) {
      return _CompletionCard(
        event: event as CompletionActivityEvent,
        onQuickComment: onQuickComment,
        onReaction: onReaction,
      );
    }
    if (event is ProgramEndingSoonActivityEvent) {
      return _ProgramEndingCard(event: event as ProgramEndingSoonActivityEvent);
    }
    if (event is CommentActivityEvent) {
      final comment = event as CommentActivityEvent;
      return _SimpleActivityCard(
        icon: Icons.comment_outlined,
        title: '${comment.authorName} commented for ${comment.athleteName}',
        detail: comment.comment,
        occurredAt: comment.occurredAt,
      );
    }
    if (event is ReactionActivityEvent) {
      final reaction = event as ReactionActivityEvent;
      final definition = coachingReactions.firstWhere(
        (item) => item.id == reaction.reactionId,
      );
      return _SimpleActivityCard(
        icon: Icons.add_reaction_outlined,
        title: '${reaction.actorName} reacted for ${reaction.athleteName}',
        detail: '${definition.symbol} ${definition.label}',
        occurredAt: reaction.occurredAt,
      );
    }
    final personalBest = event as PersonalBestActivityEvent;
    return _SimpleActivityCard(
      icon: Icons.emoji_events_outlined,
      title: '${personalBest.athleteName} set a personal best',
      detail: personalBest.summary,
      occurredAt: personalBest.occurredAt,
    );
  }
}

class _CompletionCard extends StatefulWidget {
  const _CompletionCard({
    required this.event,
    required this.onQuickComment,
    required this.onReaction,
  });

  final CompletionActivityEvent event;
  final QuickCommentCallback onQuickComment;
  final ReactionCallback onReaction;

  @override
  State<_CompletionCard> createState() => _CompletionCardState();
}

class _CompletionCardState extends State<_CompletionCard> {
  final _commentController = TextEditingController();
  bool _postingComment = false;
  String? _postingReaction;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final disabled = _postingComment || _postingReaction != null;
    return Semantics(
      container: true,
      label:
          '${event.athleteName} completed ${event.workoutName}, RPE ${event.rpe}, '
          '${event.durationMinutes} minutes',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    child: Text(
                      event.athleteName.isEmpty
                          ? '?'
                          : event.athleteName.characters.first.toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.athleteName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text('${event.workoutName} completed'),
                        Text(_formatDateTime(event.occurredAt)),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(label: Text('RPE ${event.rpe}')),
                      Chip(label: Text('${event.durationMinutes} min')),
                    ],
                  ),
                ],
              ),
              if (event.latestComment != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  label: 'Latest comment: ${event.latestComment}',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.mark_chat_read_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(event.latestComment!)),
                    ],
                  ),
                ),
              ],
              const Divider(height: 28),
              Semantics(
                container: true,
                label: 'Coaching reactions',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final reaction in coachingReactions)
                      Semantics(
                        button: true,
                        selected: event.currentTrainerReaction == reaction.id,
                        label:
                            '${reaction.label} reaction, ${event.reactionCounts[reaction.id] ?? 0}',
                        child: ChoiceChip(
                          key: Key(
                            'reaction-${event.workoutInstanceId}-${reaction.id}',
                          ),
                          avatar: _postingReaction == reaction.id
                              ? const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(reaction.symbol),
                          label: Text(
                            '${reaction.label} '
                            '${event.reactionCounts[reaction.id] ?? 0}',
                          ),
                          selected: event.currentTrainerReaction == reaction.id,
                          onSelected: disabled
                              ? null
                              : (_) => _toggleReaction(reaction.id),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: Key('quick-comment-${event.workoutInstanceId}'),
                      controller: _commentController,
                      enabled: !disabled,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Quick comment',
                        hintText: 'Add coaching feedback',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'Post quick comment',
                    child: FilledButton.icon(
                      key: Key('post-comment-${event.workoutInstanceId}'),
                      onPressed: disabled ? null : _postComment,
                      icon: _postingComment
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(_postingComment ? 'Posting…' : 'Post'),
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _postComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Enter a comment before posting.');
      return;
    }
    setState(() {
      _postingComment = true;
      _error = null;
    });
    try {
      await widget.onQuickComment(widget.event, body);
      if (!mounted) {
        return;
      }
      _commentController.clear();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not post comment: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _postingComment = false);
      }
    }
  }

  Future<void> _toggleReaction(String reactionId) async {
    setState(() {
      _postingReaction = reactionId;
      _error = null;
    });
    try {
      await widget.onReaction(widget.event, reactionId);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not update reaction: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _postingReaction = null);
      }
    }
  }
}

class _ProgramEndingCard extends StatelessWidget {
  const _ProgramEndingCard({required this.event});

  final ProgramEndingSoonActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final remaining = event.daysRemaining == 0
        ? 'Ends today'
        : '${event.daysRemaining} ${event.daysRemaining == 1 ? 'day' : 'days'} remaining';
    return Semantics(
      container: true,
      label:
          '${event.programName} for ${event.athleteName} ends ${event.endDate}, '
          '$remaining',
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.event_busy_outlined),
          title: Text('${event.programName} ends soon'),
          subtitle: Text(
            '${event.athleteName} • ${_formatExactDate(event.endDate)} • '
            '$remaining',
          ),
          trailing: Semantics(
            button: true,
            label: 'Open ${event.programName} for ${event.athleteName}',
            child: TextButton(
              onPressed: () => context.go(
                '/programs/${event.programId}/athlete/${event.athleteId}',
              ),
              child: const Text('View program'),
            ),
          ),
        ),
      ),
    );
  }
}

class _SimpleActivityCard extends StatelessWidget {
  const _SimpleActivityCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.occurredAt,
  });

  final IconData icon;
  final String title;
  final String detail;
  final DateTime occurredAt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text('$detail\n${_formatDateTime(occurredAt)}'),
        isThreeLine: true,
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              'Unable to load trainer activity',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: 'Retry loading trainer activity',
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardEmpty extends StatelessWidget {
  const _DashboardEmpty({required this.filter});

  final TrainerActivityFilter filter;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      TrainerActivityFilter.all => 'No recent client activity',
      TrainerActivityFilter.completions => 'No recent completions',
      TrainerActivityFilter.comments => 'No recent comments',
      TrainerActivityFilter.reactions => 'No recent reactions',
      TrainerActivityFilter.programs => 'No programs ending soon',
      TrainerActivityFilter.personalBests => 'Personal bests are coming later',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final hour =
      local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} at '
      '$hour:${local.minute.toString().padLeft(2, '0')} $period';
}

String _formatExactDate(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) {
    return isoDate;
  }
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
