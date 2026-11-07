import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:stage5/core/browser_smoke_status.dart';
import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/progress/presentation/climbing_progress_providers.dart';
import 'package:stage5/features/workouts/data/workout_local_day.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';

class ClimbingProgressScreen extends ConsumerStatefulWidget {
  const ClimbingProgressScreen({super.key});

  @override
  ConsumerState<ClimbingProgressScreen> createState() =>
      _ClimbingProgressScreenState();
}

class _ClimbingProgressScreenState
    extends ConsumerState<ClimbingProgressScreen> {
  ProgressPreset? _preset = ProgressPreset.month;
  late ProgressRange _range;
  ClimbingGradingSystem _system = ClimbingGradingSystem.vScale;
  final _excludedWorkouts = <(String, String)>{};

  @override
  void initState() {
    super.initState();
    _range = ProgressPreset.month.range(ref.read(progressClockProvider)());
  }

  Future<void> _pickDates() async {
    final now = ref.read(progressClockProvider)();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(start: _range.start, end: _range.end),
      helpText: 'Select 1 to 366 days',
    );
    if (picked == null || !mounted) return;
    try {
      final range = ProgressRange(start: picked.start, end: picked.end);
      setState(() {
        _preset = null;
        _range = range;
      });
    } on ArgumentError catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    }
  }

  void _refresh() {
    if (_preset != null) {
      setState(() {
        _range = _preset!.range(ref.read(progressClockProvider)());
      });
    }
    ref.invalidate(climbingProgressProvider(_range));
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(climbingProgressProvider(_range));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
        actions: [
          IconButton(
            tooltip: 'Refresh progress',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        key: const Key('climbing-progress-scroll'),
        padding: const EdgeInsets.all(20),
        children: [
          const _Heading('Climbing progress'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in ProgressPreset.values)
                ChoiceChip(
                  key: Key('progress-range-${preset.name}'),
                  label: Text(preset.label),
                  selected: _preset == preset,
                  onSelected: (_) => setState(() {
                    _preset = preset;
                    _range = preset.range(ref.read(progressClockProvider)());
                  }),
                ),
              ActionChip(
                key: const Key('progress-custom-range'),
                avatar: const Icon(Icons.date_range),
                label: Text(
                    _preset == null ? 'Custom range selected' : 'Custom dates'),
                onPressed: _pickDates,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(_range.label, key: const Key('progress-range-label')),
          const SizedBox(height: 16),
          progress.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Unable to load climbing progress'),
                    Text('$error'),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(climbingProgressProvider(_range)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (report) {
              final selected = report.excluding(_excludedWorkouts);
              if (browserAutomationEnabled) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  markBrowserSmokeSurfaceReady('athlete-progress',
                      content:
                          '${selected.current.sessionCount} climbing sessions');
                });
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WorkoutSelector(
                    available: report,
                    selected: selected,
                    excluded: _excludedWorkouts,
                    onToggle: (session, include) => setState(() {
                      if (include) {
                        _excludedWorkouts.remove(session.selectionKey);
                      } else {
                        _excludedWorkouts.add(session.selectionKey);
                      }
                    }),
                    onSelectAll: (include) => setState(() {
                      for (final session in [
                        ...report.current.sessions,
                        ...report.previous.sessions,
                      ]) {
                        if (include) {
                          _excludedWorkouts.remove(session.selectionKey);
                        } else {
                          _excludedWorkouts.add(session.selectionKey);
                        }
                      }
                    }),
                  ),
                  _ProgressContent(
                    report: selected,
                    hasAvailableWorkouts: report.current.sessionCount > 0,
                    system: _system,
                    onSystemChanged: (system) =>
                        setState(() => _system = system),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WorkoutSelector extends StatelessWidget {
  const _WorkoutSelector({
    required this.available,
    required this.selected,
    required this.excluded,
    required this.onToggle,
    required this.onSelectAll,
  });
  final ClimbingProgressReport available;
  final ClimbingProgressReport selected;
  final Set<(String, String)> excluded;
  final void Function(ClimbingSession, bool) onToggle;
  final ValueChanged<bool> onSelectAll;

  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          key: const Key('progress-workout-selector'),
          title: const Text('Choose workouts'),
          subtitle: Text('${selected.current.sessionCount} of '
              '${available.current.sessionCount} workouts included in this range'),
          childrenPadding: const EdgeInsets.all(12),
          children: [
            const Text(
              'Includes completed climbing workouts from any program and independent '
              'assignments. Uncheck individual sessions to update every chart and '
              'summary. You can also choose the preceding-period contributions. '
              'Selections stay in this view when changing dates; no workout data is changed.',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('progress-include-all'),
                  onPressed: () => onSelectAll(true),
                  child: const Text('Include all workouts'),
                ),
                TextButton(
                  key: const Key('progress-exclude-all'),
                  onPressed: () => onSelectAll(false),
                  child: const Text('Exclude all workouts'),
                ),
              ],
            ),
            for (final section in [
              ('Selected date range', available.current.sessions),
              ('Preceding comparison period', available.previous.sessions),
            ]) ...[
              _Heading(section.$1),
              if (section.$2.isEmpty)
                const Text('No climbing workouts in this period.'),
              for (final session in section.$2.reversed)
                CheckboxListTile(
                  key: Key('progress-include-${session.instanceId}'),
                  value: !excluded.contains(session.selectionKey),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(session.sourceLabel),
                  subtitle: Text(
                      '${session.recordedClimbs?.toString() ?? 'Not recorded'} recorded climbs'),
                  secondary: IconButton(
                    tooltip: 'View workout ${calendarDate(session.date)}',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () =>
                        context.push('/athlete/workouts/${session.instanceId}'),
                  ),
                  onChanged: (include) {
                    if (include != null) onToggle(session, include);
                  },
                ),
            ],
          ],
        ),
      );
}

class _ProgressContent extends StatelessWidget {
  const _ProgressContent({
    required this.report,
    required this.system,
    required this.onSystemChanged,
    required this.hasAvailableWorkouts,
  });
  final ClimbingProgressReport report;
  final ClimbingGradingSystem system;
  final ValueChanged<ClimbingGradingSystem> onSystemChanged;
  final bool hasAvailableWorkouts;

  @override
  Widget build(BuildContext context) {
    final current = report.current;
    final previous = report.previous;
    final gradeCounts = current.gradeCounts(system);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryCard(
              key: const Key('progress-summary-sessions'),
              title: 'Climbing sessions',
              value: '${current.sessionCount}',
              comparison:
                  '${previous.sessionCount} in preceding ${report.range.days} days',
            ),
            _SummaryCard(
              key: const Key('progress-summary-climbs'),
              title: 'Recorded completed climbs',
              value: current.recordedClimbs?.toString() ?? 'Not recorded',
              comparison:
                  '${previous.recordedClimbs?.toString() ?? 'Not recorded'} in preceding period',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Dates use actual workout completion time in your local timezone. '
          'One completed workout containing climbing counts as one session.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Counts combine sent single routes, all prescribed climbs in completed '
          'circuit rows, and recorded Free Climbing counts. Circuit and Free '
          'Climbing counts do not establish sends. Unfinished circuit rows and '
          'omitted results are not zero.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (current.incompleteSessions > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${current.incompleteSessions} sessions have missing counts or '
              'legacy grades. Recorded totals may understate volume; legacy '
              'colors/grades are not ranked.',
              key: const Key('progress-coverage-note'),
            ),
          ),
        if (current.sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(hasAvailableWorkouts
                ? 'No workouts selected for this range.'
                : 'No completed climbing workouts in this range.'),
          ),
        const SizedBox(height: 24),
        const _Heading('Sessions over time'),
        _BucketChart(
          keyPrefix: 'sessions',
          buckets: report.buckets,
          value: (summary) => summary.sessionCount,
          label: (summary) => '${summary.sessionCount} sessions',
          onTap: (bucket) => _showSources(
              context, bucket.summary.sessions, bucket.range.label),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in ClimbingGradingSystem.values)
              ChoiceChip(
                key: Key('progress-system-${value.name}'),
                label: Text(value.label),
                selected: system == value,
                onSelected: (_) => onSystemChanged(value),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _Heading('Recorded climbs by grade - ${system.label}'),
        if (gradeCounts.isEmpty)
          const Text(
              'No recorded completed climb counts for this grading system.'),
        for (final entry in gradeCounts.entries)
          ListTile(
            key: Key('progress-grade-${system.name}-${entry.key}'),
            contentPadding: EdgeInsets.zero,
            title: Text(entry.key),
            subtitle: LinearProgressIndicator(
              value: entry.value / gradeCounts.values.reduce(math.max),
              minHeight: 8,
            ),
            trailing: Text('${entry.value} recorded climbs'),
            onTap: () => _showSources(
              context,
              current.sessions
                  .where((session) => session.climbs.any(
                        (climb) =>
                            climb.system == system &&
                            climb.grade == entry.key &&
                            climb.count > 0,
                      ))
                  .toList(),
              '${system.label}: ${entry.key}',
            ),
          ),
        const SizedBox(height: 24),
        const _Heading('Recorded climb volume over time'),
        _BucketChart(
          keyPrefix: 'volume',
          buckets: report.buckets,
          value: (summary) {
            return summary.recordedFor(system);
          },
          label: (summary) {
            final count = summary.recordedFor(system);
            return count == null ? 'Not recorded' : '$count climbs';
          },
          onTap: (bucket) => _showSources(
              context, bucket.summary.sessions, bucket.range.label),
        ),
        const SizedBox(height: 24),
        const _Heading('Highest confirmed sent grade'),
        Text(
          '${current.highestSend(system) ?? 'No recorded sends'}'
          ' - preceding period: ${previous.highestSend(system) ?? 'No recorded sends'}',
          key: const Key('progress-highest-send'),
        ),
        const Text(
          'Confirmed single-route sends only. Grades are ordered within one '
          'system, not converted between systems or averaged. Different routes '
          'and venues are not necessarily equivalent.',
        ),
        _BucketChart(
          keyPrefix: 'sends',
          buckets: report.buckets,
          value: (summary) {
            final grade = summary.highestSend(system);
            return grade == null ? null : system.grades.indexOf(grade) + 1;
          },
          label: (summary) => summary.highestSend(system) ?? 'No sends',
          onTap: (bucket) => _showSources(
            context,
            bucket.summary.sessions
                .where((session) => session.routes.any(
                      (route) => route.system == system && route.sent == true,
                    ))
                .toList(),
            'Confirmed sends: ${bucket.range.label}',
          ),
        ),
        const SizedBox(height: 24),
        const _Heading('Single-route attempts and sends'),
        const Text(
          'Attempts are the recorded attempts in that workout, not accumulated '
          'attempts across sessions. Only confirmed sends have attempts-to-send.',
        ),
        if (!current.sessions.any(
            (session) => session.routes.any((route) => route.system == system)))
          const Text('No single-route results for this grading system.'),
        for (final session in current.sessions)
          for (final route in session.routes.where((r) => r.system == system))
            ListTile(
              title: Text('${route.grade} - ${route.name}'),
              subtitle: Text(
                  '${calendarDate(session.date)} - ${_routeResult(route)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  context.push('/athlete/workouts/${session.instanceId}'),
            ),
        const SizedBox(height: 24),
        const _Heading('Circuit completion trends'),
        const Text(
          'Whole rows completed / prescribed rows. Each immutable workout '
          'version is shown separately; changed prescriptions are not compared '
          'as equivalent performance. Partial climb counts are unknown.',
        ),
        _CircuitTrends(report: report),
        const SizedBox(height: 24),
        const _Heading('Source workouts'),
        for (final session in current.sessions.reversed)
          _SessionTile(session: session),
      ],
    );
  }
}

class _CircuitTrends extends StatelessWidget {
  const _CircuitTrends({required this.report});
  final ClimbingProgressReport report;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<(ClimbingSession, CircuitPerformance)>>{};
    for (final session in report.current.sessions) {
      for (final circuit in session.circuits) {
        groups.putIfAbsent(circuit.key, () => []).add((session, circuit));
      }
    }
    if (groups.isEmpty)
      return const Text('No recorded climbing circuit results.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups.values)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${group.first.$2.name} - workout version ${group.first.$1.version}',
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final row in group.first.$2.prescription)
                    Text(
                        '${row.gradingSystem.label}: ${row.grade} x ${row.climbs}'
                        '${row.maxAttemptsPerClimb == null ? '' : ', max ${row.maxAttemptsPerClimb} attempts per climb'}'),
                  for (final previousSession in report.previous.sessions)
                    for (final circuit in previousSession.circuits
                        .where((circuit) => circuit.key == group.first.$2.key))
                      Text(
                          'Preceding period ${calendarDate(previousSession.date)}: '
                          '${circuit.completedRows}/${circuit.totalRows} rows'),
                  for (final entry in group)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${calendarDate(entry.$1.date)}: '
                          '${entry.$2.completedRows}/${entry.$2.totalRows} rows'),
                      subtitle: LinearProgressIndicator(
                        value: entry.$2.completedRows / entry.$2.totalRows,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context
                          .push('/athlete/workouts/${entry.$1.instanceId}'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BucketChart extends StatelessWidget {
  const _BucketChart({
    required this.keyPrefix,
    required this.buckets,
    required this.value,
    required this.label,
    required this.onTap,
  });
  final String keyPrefix;
  final List<ProgressBucket> buckets;
  final int? Function(ClimbingSummary) value;
  final String Function(ClimbingSummary) label;
  final ValueChanged<ProgressBucket> onTap;

  @override
  Widget build(BuildContext context) {
    final maxValue =
        buckets.map((b) => value(b.summary) ?? 0).fold<int>(1, math.max);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(constraints.maxWidth, buckets.length * 84.0),
            height: 210,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < buckets.length; index++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      label:
                          '${buckets[index].range.label}: ${label(buckets[index].summary)}. View source workouts.',
                      child: InkWell(
                        key: Key('progress-$keyPrefix-$index'),
                        onTap: () => onTap(buckets[index]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(label(buckets[index].summary),
                                  textAlign: TextAlign.center,
                                  style:
                                      Theme.of(context).textTheme.labelSmall),
                              const SizedBox(height: 4),
                              Container(
                                height: math.max(
                                    2,
                                    (value(buckets[index].summary) ?? 0) /
                                        maxValue *
                                        130),
                                decoration: BoxDecoration(
                                  color: value(buckets[index].summary) == null
                                      ? Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                      : Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                  calendarDate(buckets[index].range.start)
                                      .substring(5),
                                  style:
                                      Theme.of(context).textTheme.labelSmall),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showSources(
  BuildContext context,
  List<ClimbingSession> sessions,
  String title,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: ListView(
          key: const Key('progress-source-sheet'),
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                tooltip: 'Close source workouts',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ]),
            if (sessions.isEmpty)
              const Text('No recorded workouts for this chart point.'),
            for (final session in sessions.reversed) ...[
              _SessionTile(session: session, closeSheet: true),
              for (final route in session.routes)
                Text(
                    '${route.system.label}: ${route.grade} - ${_routeResult(route)}'),
              for (final circuit in session.circuits)
                Text(
                    '${circuit.name}: ${circuit.completedRows}/${circuit.totalRows} whole rows'),
              for (final climb
                  in session.climbs.where((entry) => entry.count > 0))
                Text(
                    '${climb.system.label}: ${climb.grade} - ${climb.count} recorded climbs'),
              const Divider(),
            ],
          ],
        ),
      ),
    );

String _routeResult(RoutePerformance route) =>
    '${route.sent == true ? 'Sent' : route.sent == false ? 'Not sent' : 'Send not recorded'}'
    ' - ${route.attempts == null ? 'attempts not recorded' : '${route.attempts} recorded attempts'}';

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, this.closeSheet = false});
  final ClimbingSession session;
  final bool closeSheet;

  @override
  Widget build(BuildContext context) => ListTile(
        key: Key('progress-workout-${session.instanceId}'),
        contentPadding: EdgeInsets.zero,
        title: Text(session.sourceLabel),
        subtitle: Text(
            '${session.recordedClimbs?.toString() ?? 'Not recorded'} recorded climbs'
            '${session.unrecordedBlocks > 0 ? ' - some counts unrecorded' : ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          final router = GoRouter.of(context);
          if (closeSheet) Navigator.pop(context);
          router.push('/athlete/workouts/${session.instanceId}');
        },
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.title,
      required this.value,
      required this.comparison,
      super.key});
  final String title;
  final String value;
  final String comparison;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 280,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(value, style: Theme.of(context).textTheme.headlineMedium),
                Text(comparison),
              ],
            ),
          ),
        ),
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(text, style: Theme.of(context).textTheme.titleLarge),
        ),
      );
}
