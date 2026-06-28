import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/exercises/domain/exercise_template.dart';
import 'package:stage4/features/exercises/domain/youtube_url.dart';
import 'package:stage4/features/exercises/presentation/exercise_providers.dart';
import 'package:stage4/features/exercises/presentation/youtube_embed.dart';

/// Read-only detail view for an exercise template.
///
/// Shows the exercise's description and instructions, and embeds a YouTube
/// player when [ExerciseTemplate.videoUrl] is a recognized YouTube link.
/// Non-YouTube URLs fall back to an "Open link" button. The same view is used
/// by everyone (coaches and athletes); an Edit action is only shown to the
/// exercise's creator.
class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(exerciseTemplateRepositoryProvider);
    final currentUid = ref.watch(authStateProvider).value?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise'),
      ),
      body: FutureBuilder<ExerciseTemplate?>(
        future: repo.getById(exerciseId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final exercise = snapshot.data;
          if (exercise == null) {
            return const Center(child: Text('Exercise not found'));
          }
          return _ExerciseDetailBody(
            exercise: exercise,
            canEdit: currentUid != null && exercise.createdBy == currentUid,
          );
        },
      ),
    );
  }
}

class _ExerciseDetailBody extends StatelessWidget {
  const _ExerciseDetailBody({required this.exercise, required this.canEdit});

  final ExerciseTemplate exercise;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final videoUrl = exercise.videoUrl;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(exercise.name, style: theme.textTheme.headlineSmall),
            ),
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit exercise',
                onPressed: () => context.push('/exercises/${exercise.id}/edit'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (videoUrl != null && videoUrl.trim().isNotEmpty) ...[
          Text('Video', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _ExerciseVideo(url: videoUrl.trim()),
          const SizedBox(height: 24),
        ],
        Text('Description', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(exercise.description, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),
        Text('Instructions', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(exercise.instructions, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// Renders an embedded YouTube player for supported URLs, or an "Open link"
/// fallback for any other URL.
class _ExerciseVideo extends StatelessWidget {
  const _ExerciseVideo({required this.url});

  final String url;

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final videoId = extractYoutubeId(url);
    if (videoId != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: buildYoutubeEmbed(videoId),
          ),
        ),
      );
    }

    // Unsupported URL — offer to open it externally.
    return Card(
      child: ListTile(
        leading: const Icon(Icons.open_in_new),
        title: const Text('Open video link'),
        subtitle: Text(
          url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: _openExternally,
      ),
    );
  }
}
