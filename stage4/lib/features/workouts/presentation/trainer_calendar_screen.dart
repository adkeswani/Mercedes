import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/auth/presentation/app_entry_providers.dart';
import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/programs/domain/program.dart';
import 'package:stage4/features/programs/presentation/enrollment_providers.dart';
import 'package:stage4/features/programs/presentation/program_providers.dart';
import 'package:stage4/features/workouts/domain/workout_instance.dart';
import 'package:stage4/features/workouts/presentation/workout_instance_providers.dart';

/// Per-athlete trainer calendar.
///
/// A coach selects one of their enrolled athletes and sees a month-at-a-time
/// calendar of every workout they have assigned that athlete, color-coded by
/// program. Tapping a day reveals that day's workouts (which can be opened,
/// rescheduled, or cancelled) and actions to assign a program or a single
/// workout to that day.
class TrainerCalendarScreen extends ConsumerStatefulWidget {
  const TrainerCalendarScreen({super.key, this.athleteId});

  /// When provided, the calendar opens focused on this athlete instead of
  /// defaulting to the first enrolled athlete.
  final String? athleteId;

  @override
  ConsumerState<TrainerCalendarScreen> createState() =>
      _TrainerCalendarScreenState();
}

class _TrainerCalendarScreenState extends ConsumerState<TrainerCalendarScreen> {
  String? _selectedAthleteId;
  late DateTime _month;
  final _athleteNames = <String, String>{};

  /// Deterministic palette for program color-coding.
  static const _palette = [
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFE53935),
    Color(0xFF8E24AA),
    Color(0xFFF4511E),
    Color(0xFF00897B),
    Color(0xFF6D4C41),
    Color(0xFF3949AB),
  ];

  @override
  void initState() {
    super.initState();
    _selectedAthleteId = widget.athleteId;
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _previousMonth() {
    setState(() => _month = DateTime(_month.year, _month.month - 1));
  }

  void _nextMonth() {
    setState(() => _month = DateTime(_month.year, _month.month + 1));
  }

  String _formatIsoDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _monthLabel(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  Color _colorForProgram(String programId, List<Program> programs) {
    final sorted = [...programs]..sort((a, b) => a.id.compareTo(b.id));
    final index = sorted.indexWhere((p) => p.id == programId);
    if (index < 0) return Colors.grey;
    return _palette[index % _palette.length];
  }

  void _resolveNames(List enrollments) {
    final profileRepo = ref.read(userProfileRepositoryProvider);
    for (final e in enrollments) {
      final id = e.athleteId as String;
      if (!_athleteNames.containsKey(id)) {
        _athleteNames[id] = id;
        profileRepo.getUserProfile(id).then((profile) {
          if (profile != null && mounted) {
            setState(() => _athleteNames[id] = profile.displayName);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrollmentsAsync = ref.watch(ownerEnrollmentsProvider);
    final programs = ref.watch(programsProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Athlete Calendar')),
      body: enrollmentsAsync.when(
        data: (enrollments) {
          _resolveNames(enrollments);
          final athleteIds =
              {for (final e in enrollments) e.athleteId}.toList();
          if (athleteIds.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No athletes enrolled in your programs yet. Enroll an '
                  'athlete from a program roster to see their calendar.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (_selectedAthleteId == null ||
              !athleteIds.contains(_selectedAthleteId)) {
            _selectedAthleteId = athleteIds.first;
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedAthleteId,
                  decoration: const InputDecoration(
                    labelText: 'Athlete',
                    border: OutlineInputBorder(),
                  ),
                  items: athleteIds.map((id) {
                    return DropdownMenuItem(
                      value: id,
                      child: Text(_athleteNames[id] ?? id),
                    );
                  }).toList(),
                  onChanged: (value) =>
                      setState(() => _selectedAthleteId = value),
                ),
              ),
              _buildMonthNav(context),
              const Divider(height: 1),
              Expanded(child: _buildCalendarBody(context, programs)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildMonthNav(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _previousMonth,
          ),
          Text(
            _monthLabel(_month),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _nextMonth,
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarBody(BuildContext context, List<Program> programs) {
    final athleteId = _selectedAthleteId;
    if (athleteId == null) return const SizedBox.shrink();

    final firstOfMonth = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final range = AthleteCalendarKey(
      athleteId: athleteId,
      startDate: _formatIsoDate(firstOfMonth),
      endDate: _formatIsoDate(DateTime(_month.year, _month.month, daysInMonth)),
    );
    final instancesAsync = ref.watch(athleteCalendarProvider(range));

    return instancesAsync.when(
      data: (instances) {
        final byDate = <String, List<WorkoutInstance>>{};
        for (final i in instances) {
          byDate.putIfAbsent(i.scheduledDate, () => []).add(i);
        }
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: _buildGrid(context, firstOfMonth, daysInMonth, byDate,
                    programs),
              ),
            ),
            _buildLegend(context, instances, programs),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    DateTime firstOfMonth,
    int daysInMonth,
    Map<String, List<WorkoutInstance>> byDate,
    List<Program> programs,
  ) {
    // Monday-based leading offset.
    final leading = firstOfMonth.weekday - 1;
    final totalCells = leading + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final todayIso = _formatIsoDate(DateTime.now());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _buildCell(
                    context,
                    cellIndex: row * 7 + col,
                    leading: leading,
                    daysInMonth: daysInMonth,
                    firstOfMonth: firstOfMonth,
                    byDate: byDate,
                    programs: programs,
                    todayIso: todayIso,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCell(
    BuildContext context, {
    required int cellIndex,
    required int leading,
    required int daysInMonth,
    required DateTime firstOfMonth,
    required Map<String, List<WorkoutInstance>> byDate,
    required List<Program> programs,
    required String todayIso,
  }) {
    final dayNum = cellIndex - leading + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 64);
    }
    final date = DateTime(firstOfMonth.year, firstOfMonth.month, dayNum);
    final iso = _formatIsoDate(date);
    final dayInstances = byDate[iso] ?? const [];
    final isToday = iso == todayIso;

    return InkWell(
      onTap: () => _openDay(context, date, dayInstances, programs),
      child: Container(
        height: 64,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          color: isToday
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$dayNum', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 2),
            Expanded(
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  for (final i in dayInstances.take(6))
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i.status == WorkoutInstanceStatus.cancelled
                            ? Colors.grey.shade400
                            : _colorForProgram(i.programId, programs),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(
    BuildContext context,
    List<WorkoutInstance> instances,
    List<Program> programs,
  ) {
    final programIds = {for (final i in instances) i.programId}.toList();
    if (programIds.isEmpty) return const SizedBox.shrink();
    final nameById = {for (final p in programs) p.id: p.name};

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final id in programIds)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _colorForProgram(id, programs),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  nameById[id] ?? 'Program',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _openDay(
    BuildContext context,
    DateTime date,
    List<WorkoutInstance> instances,
    List<Program> programs,
  ) {
    final nameById = {for (final p in programs) p.id: p.name};
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _formatIsoDate(date),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (instances.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No workouts on this day'),
                  )
                else
                  ...instances.map((i) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.circle,
                          size: 14,
                          color: i.status == WorkoutInstanceStatus.cancelled
                              ? Colors.grey
                              : _colorForProgram(i.programId, programs),
                        ),
                        title: Text(nameById[i.programId] ?? 'Program'),
                        subtitle: Text(
                          '${i.workoutType.name} · ${i.status.name}',
                        ),
                        trailing: i.isScheduled
                            ? PopupMenuButton<String>(
                                onSelected: (value) async {
                                  Navigator.of(sheetContext).pop();
                                  if (value == 'open') {
                                    context.push(
                                      '/workouts/complete/${i.id}',
                                    );
                                  } else if (value == 'reschedule') {
                                    await _reschedule(context, i);
                                  } else if (value == 'cancel') {
                                    await _cancel(context, i);
                                  } else if (value == 'delete-program') {
                                    await _deleteProgram(context, i);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'open',
                                    child: Text('Open / Complete'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'reschedule',
                                    child: Text('Reschedule'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'cancel',
                                    child: Text('Cancel'),
                                  ),
                                  if (i.programAssignmentId != null)
                                    const PopupMenuItem(
                                      value: 'delete-program',
                                      child: Text('Delete entire program'),
                                    ),
                                ],
                              )
                            : IconButton(
                                icon: const Icon(Icons.chevron_right),
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  context.push('/workouts/complete/${i.id}');
                                },
                              ),
                      )),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add),
                  title: const Text('Assign workout or program'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _assignOnDay(context, date);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _assignOnDay(BuildContext context, DateTime date) {
    final athleteId = _selectedAthleteId;
    if (athleteId == null) return;
    final iso = _formatIsoDate(date);
    context.push('/assign?athleteId=$athleteId&date=$iso');
  }

  Future<void> _reschedule(BuildContext context, WorkoutInstance instance) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    final current = DateTime.tryParse(instance.scheduledDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    try {
      await ref.read(workoutInstanceRepositoryProvider).rescheduleInstance(
            instanceId: instance.id,
            newDate: _formatIsoDate(picked),
            ownerId: uid,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved to ${_formatIsoDate(picked)}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reschedule: $e')),
        );
      }
    }
  }

  Future<void> _cancel(BuildContext context, WorkoutInstance instance) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    try {
      await ref.read(workoutInstanceRepositoryProvider).cancelInstance(
            instanceId: instance.id,
            ownerId: uid,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workout cancelled')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel: $e')),
        );
      }
    }
  }

  Future<void> _deleteProgram(BuildContext context, WorkoutInstance instance) async {
    final uid = ref.read(authStateProvider).value?.uid;
    final assignmentId = instance.programAssignmentId;
    if (uid == null || assignmentId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entire program?'),
        content: const Text(
          'This permanently deletes every workout from this assignment, '
          'including completed ones. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final count =
          await ref.read(workoutInstanceRepositoryProvider).deleteProgramAssignment(
                programAssignmentId: assignmentId,
                ownerId: uid,
              );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $count workout(s)')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }
}
