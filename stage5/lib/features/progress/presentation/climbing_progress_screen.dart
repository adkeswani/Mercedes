import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:stage5/core/browser_smoke_status.dart';
import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/progress/presentation/climbing_progress_providers.dart';
import 'package:stage5/features/progress/presentation/progress_line_chart.dart';
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
  bool _sentOnly = false;
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

  void _selectWorkouts(Iterable<ClimbingSession> sessions, bool include) {
    setState(() {
      for (final session in sessions) {
        if (include) {
          _excludedWorkouts.remove(session.selectionKey);
        } else {
          _excludedWorkouts.add(session.selectionKey);
        }
      }
    });
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
                  _preset == null ? 'Custom range selected' : 'Custom dates',
                ),
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
                  markBrowserSmokeSurfaceReady(
                    'athlete-progress',
                    content:
                        '${selected.current.sessionCount} climbing sessions',
                  );
                });
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WorkoutSelector(
                    available: report,
                    selected: selected,
                    excluded: _excludedWorkouts,
                    onToggle: (session, include) =>
                        _selectWorkouts([session], include),
                    onSelectAll: (include) => _selectWorkouts(
                      [
                        ...report.current.sessions,
                        ...report.previous.sessions,
                      ],
                      include,
                    ),
                    onSelectGroup: (group, include) =>
                        _selectWorkouts(group.sessions, include),
                  ),
                  _ProgressContent(
                    report: _sentOnly ? selected.sentOnly() : selected,
                    hasAvailableWorkouts: report.current.sessionCount > 0,
                    system: _system,
                    onSystemChanged: (system) =>
                        setState(() => _system = system),
                    sentOnly: _sentOnly,
                    onSentOnlyChanged: (value) =>
                        setState(() => _sentOnly = value),
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
    required this.onSelectGroup,
  });
  final ClimbingProgressReport available;
  final ClimbingProgressReport selected;
  final Set<(String, String)> excluded;
  final void Function(ClimbingSession, bool) onToggle;
  final ValueChanged<bool> onSelectAll;
  final void Function(ProgressWorkoutGroup, bool) onSelectGroup;

  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          key: const Key('progress-workout-selector'),
          title: const Text('Choose workouts'),
          subtitle: Text('${selected.current.sessionCount} of '
              '${available.current.sessionCount} workouts included in this range'),
          childrenPadding: const EdgeInsets.all(12),
          children: [
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
            for (final group in available.workoutGroups)
              ExpansionTile(
                key: Key('progress-group-${group.key}'),
                leading: Checkbox(
                  key: Key('progress-group-check-${group.key}'),
                  tristate: true,
                  value: group.selectionValue(excluded),
                  semanticLabel: 'Include workouts from ${group.title}',
                  onChanged: (_) => onSelectGroup(
                    group,
                    group.selectionValue(excluded) != true,
                  ),
                ),
                title: Text(group.title),
                subtitle: Text(
                    '${group.sessions.where((session) => !excluded.contains(session.selectionKey)).length} of '
                    '${group.sessions.length} selected'),
                children: [
                  for (final session in group.sessions)
                    CheckboxListTile(
                      key: Key('progress-include-${session.instanceId}'),
                      value: !excluded.contains(session.selectionKey),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(session.sourceLabel),
                      subtitle: Text(
                          '${session.recordedClimbs?.toString() ?? 'Not recorded'} recorded climbs'
                          ' · ${available.range.contains(session.date) ? 'Selected range' : 'Preceding period'}'),
                      secondary: IconButton(
                        tooltip: 'View workout ${calendarDate(session.date)}',
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => context
                            .push('/athlete/workouts/${session.instanceId}'),
                      ),
                      onChanged: (include) {
                        if (include != null) onToggle(session, include);
                      },
                    ),
                ],
              ),
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
    required this.sentOnly,
    required this.onSentOnlyChanged,
  });
  final ClimbingProgressReport report;
  final ClimbingGradingSystem system;
  final ValueChanged<ClimbingGradingSystem> onSystemChanged;
  final bool hasAvailableWorkouts;
  final bool sentOnly;
  final ValueChanged<bool> onSentOnlyChanged;

  @override
  Widget build(BuildContext context) {
    final current = report.current;
    final previous = report.previous;
    final gradeCounts = current.gradeCounts(system);
    final weeks = report.weeklyBuckets;
    final sendChart = _ProgressChartCard(
      title: sentOnly
          ? 'Highest grade sent each week'
          : 'Highest grade climbed each week',
      children: [
        Text(
          '${current.highestGrade(system) ?? 'No recorded climbs'}'
          ' - preceding period: ${previous.highestGrade(system) ?? 'No recorded climbs'}',
          key: const Key('progress-highest-send'),
        ),
        ProgressLineChart(
          keyPrefix: 'sends',
          buckets: weeks,
          emptyLabel: 'No recorded climbs in this range.',
          valueLabel: (rank) => rank == 0 ? '-' : system.grades[rank - 1],
          series: [
            ProgressLineSeries(
              id: 'sends',
              label: system.label,
              values: [
                for (final week in weeks)
                  if (week.summary.highestGrade(system) case final String grade)
                    system.grades.indexOf(grade) + 1
                  else
                    null,
              ],
            ),
          ],
          onTap: (index, _) => _showSources(
            context,
            weeks[index]
                .summary
                .sessions
                .where(
                  (session) => session.routes.any(
                    (route) =>
                        route.system == system &&
                        (route.sent != null || (route.attempts ?? 0) > 0),
                  ),
                )
                .toList(),
            '${sentOnly ? 'Sent climbs' : 'Climbs'}: ${weeks[index].range.label}',
          ),
        ),
      ],
    );
    final volumeChart = _ProgressChartCard(
      title: 'Total recorded climbs each week',
      children: [
        ProgressLineChart(
          keyPrefix: 'volume',
          buckets: weeks,
          series: [
            ProgressLineSeries(
              id: 'volume',
              label: 'Climbs',
              values: [
                for (final week in weeks)
                  week.summary.sessions.isEmpty
                      ? 0
                      : week.summary.recordedClimbs,
              ],
            ),
          ],
          onTap: (index, _) => _showSources(
            context,
            weeks[index].summary.sessions,
            weeks[index].range.label,
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                key: const Key('progress-summary-sessions'),
                title: 'Climbing sessions',
                value: '${current.sessionCount}',
                comparison:
                    '${previous.sessionCount} in preceding ${report.range.days} days',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                key: const Key('progress-summary-climbs'),
                title: sentOnly ? 'Recorded sent climbs' : 'Recorded climbs',
                value: current.recordedClimbs?.toString() ?? 'Not recorded',
                comparison:
                    '${previous.recordedClimbs?.toString() ?? 'Not recorded'} in preceding period',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (current.sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              hasAvailableWorkouts
                  ? 'No workouts selected for this range.'
                  : 'No completed climbing workouts in this range.',
            ),
          ),
        if (current.sessions.isNotEmpty) ...[
          CheckboxListTile(
            key: const Key('progress-sent-only'),
            value: sentOnly,
            title: const Text('Sent climbs only'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) {
              if (value != null) onSentOnlyChanged(value);
            },
          ),
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
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 900
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: sendChart),
                      const SizedBox(width: 16),
                      Expanded(child: volumeChart),
                    ],
                  )
                : Column(
                    children: [
                      sendChart,
                      const SizedBox(height: 16),
                      volumeChart,
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          _ProgressChartCard(
            title: 'Recorded climbs by grade each week',
            children: [
              ProgressLineChart(
                key: const Key('progress-grade-chart'),
                keyPrefix: 'grade-volume',
                buckets: weeks,
                showLegend: true,
                emptyLabel: 'No recorded climbs for this grading system.',
                series: [
                  for (final grade in gradeCounts.keys)
                    ProgressLineSeries(
                      id: '${system.name}-$grade',
                      label: grade,
                      values: [
                        for (final week in weeks)
                          week.summary.sessions.isNotEmpty &&
                                  week.summary.recordedFor(system) == null
                              ? null
                              : week.summary.gradeCounts(system)[grade] ?? 0,
                      ],
                    ),
                ],
                onTap: (index, visibleGrades) => _showSources(
                  context,
                  weeks[index]
                      .summary
                      .sessions
                      .where(
                        (session) => session.climbs.any(
                          (climb) =>
                              climb.system == system &&
                              climb.count > 0 &&
                              visibleGrades
                                  .contains('${system.name}-${climb.grade}'),
                        ),
                      )
                      .toList(),
                  '${system.label}: ${weeks[index].range.label}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _Heading('Attempts and sends'),
          if (!current.sessions.any(
            (session) => session.routes.any((route) => route.system == system),
          ))
            const Text('No climb results for this grading system.'),
          for (final session in current.sessions)
            for (final route in session.routes.where((r) => r.system == system))
              ListTile(
                title: Text('${route.grade} - ${route.name}'),
                subtitle: Text(
                  '${calendarDate(session.date)} - ${_routeResult(route)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    context.push('/athlete/workouts/${session.instanceId}'),
              ),
          const SizedBox(height: 24),
          const _Heading('Circuit completion trends'),
          _CircuitTrends(report: report),
          const SizedBox(height: 24),
          const _Heading('Source workouts'),
          for (final session in current.sessions.reversed)
            _SessionTile(session: session),
        ],
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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

class _ProgressChartCard extends StatelessWidget {
  const _ProgressChartCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_Heading(title), ...children],
          ),
        ),
      );
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close source workouts',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (sessions.isEmpty)
              const Text('No recorded workouts for this chart point.'),
            for (final session in sessions.reversed) ...[
              _SessionTile(session: session, closeSheet: true),
              for (final route in session.routes)
                Text(
                  '${route.system.label}: ${route.grade} - ${_routeResult(route)}',
                ),
              for (final circuit in session.circuits)
                Text(
                  '${circuit.name}: ${circuit.completedRows}/${circuit.totalRows} whole rows',
                ),
              for (final climb
                  in session.climbs.where((entry) => entry.count > 0))
                Text(
                  '${climb.system.label}: ${climb.grade} - ${climb.count} recorded climbs',
                ),
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
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.comparison,
    super.key,
  });
  final String title;
  final String value;
  final String comparison;

  @override
  Widget build(BuildContext context) => Card(
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
