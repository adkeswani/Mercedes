import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';

class WorkoutTypePieChart extends StatelessWidget {
  const WorkoutTypePieChart({required this.summary, super.key});

  final ClimbingSummary summary;

  @override
  Widget build(BuildContext context) {
    final counts = summary.workoutTypeCounts;
    final total = summary.sessionCount;
    final colors = {
      for (final type in counts.keys)
        type: HSVColor.fromAHSV(
          1,
          (type.index * 137.5 + 210) % 360,
          .7,
          Theme.of(context).brightness == Brightness.dark ? .95 : .65,
        ).toColor(),
    };
    return Card(
      key: const Key('progress-workout-types'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Completed workouts by type',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('$total completed climbing workouts in the selected range'),
            if (total == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No completed climbing workouts selected.'),
              )
            else ...[
              const SizedBox(height: 16),
              Center(
                child: Semantics(
                  label: 'Workout type distribution',
                  image: true,
                  child: SizedBox.square(
                    dimension: 220,
                    child: CustomPaint(
                      key: const Key('progress-workout-type-pie'),
                      painter: WorkoutTypePiePainter(
                        counts: counts,
                        colors: colors,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
                  for (final entry in counts.entries)
                    Row(
                      key: Key('progress-workout-type-${entry.key.name}'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          color: colors[entry.key],
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${_typeLabel(entry.key)}: '
                            '${(100 * entry.value / total).toStringAsFixed(1)}% '
                            '(${entry.value})',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _typeLabel(WorkoutType type) => switch (type) {
      _ when type.isClimbing => type.label,
      WorkoutType.powerEndurance => 'Power Endurance',
      WorkoutType.fullBody => 'Full Body',
      _ => '${type.name[0].toUpperCase()}${type.name.substring(1)}',
    };

class WorkoutTypePiePainter extends CustomPainter {
  WorkoutTypePiePainter({
    required Map<WorkoutType, int> counts,
    required Map<WorkoutType, Color> colors,
  })  : counts = Map.unmodifiable(counts),
        colors = Map.unmodifiable(colors);

  final Map<WorkoutType, int> counts;
  final Map<WorkoutType, Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = counts.values.fold<int>(0, (sum, count) => sum + count);
    if (total == 0) return;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: math.min(size.width, size.height) / 2,
    );
    var start = -math.pi / 2;
    for (final entry in counts.entries) {
      final sweep = 2 * math.pi * entry.value / total;
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()..color = colors[entry.key]!,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(WorkoutTypePiePainter oldDelegate) =>
      !mapEquals(counts, oldDelegate.counts) ||
      !mapEquals(colors, oldDelegate.colors);
}
