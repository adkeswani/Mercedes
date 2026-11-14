import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/workouts/data/workout_local_day.dart';

class ProgressLineSeries {
  ProgressLineSeries({
    required this.id,
    required this.label,
    required List<int?> values,
  }) : values = List.unmodifiable(values);

  final String id;
  final String label;
  final List<int?> values;
}

class ProgressLineChart extends StatefulWidget {
  const ProgressLineChart({
    required this.keyPrefix,
    required this.buckets,
    required this.series,
    required this.onTap,
    this.showLegend = false,
    this.valueLabel,
    this.emptyLabel = 'No recorded data in this range.',
    super.key,
  });

  final String keyPrefix;
  final List<ProgressBucket> buckets;
  final List<ProgressLineSeries> series;
  final void Function(int, Set<String>) onTap;
  final bool showLegend;
  final String Function(int)? valueLabel;
  final String emptyLabel;

  @override
  State<ProgressLineChart> createState() => _ProgressLineChartState();
}

class _ProgressLineChartState extends State<ProgressLineChart> {
  final _excluded = <String>{};

  @override
  Widget build(BuildContext context) {
    for (final series in widget.series) {
      if (series.values.length != widget.buckets.length) {
        throw StateError('Each progress line must have one value per week.');
      }
      if (series.values.any((value) => value != null && value < 0)) {
        throw StateError('Progress line values must be nonnegative.');
      }
    }
    final active = widget.series
        .where((series) => !_excluded.contains(series.id))
        .toList();
    final colors = {
      for (var index = 0; index < widget.series.length; index++)
        widget.series[index].id: widget.series.length == 1
            ? Theme.of(context).colorScheme.primary
            : HSVColor.fromAHSV(
                1,
                (index * 137.5 + 210) % 360,
                .7,
                Theme.of(context).brightness == Brightness.dark ? .95 : .65,
              ).toColor(),
    };
    final values = active.expand((series) => series.values).whereType<int>();
    final maximum = values.fold<int>(1, math.max);
    String format(int value) => widget.valueLabel?.call(value) ?? '$value';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (values.isEmpty)
          SizedBox(
            height: 220,
            child: Center(
              child: Text(
                active.isEmpty && widget.series.isNotEmpty
                    ? 'Choose a grade to show its line.'
                    : widget.emptyLabel,
              ),
            ),
          )
        else
          SizedBox(
            height: 240,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, 240);
                final plot = ProgressLineChartPainter.plotRect(size);
                final step = widget.buckets.length <= 1
                    ? plot.width
                    : plot.width / (widget.buckets.length - 1);
                double x(int index) => widget.buckets.length == 1
                    ? plot.center.dx
                    : plot.left + index * step;
                final stride = math.max(
                  1,
                  ((widget.buckets.length - 1) / math.max(1, plot.width ~/ 90))
                      .ceil(),
                );
                final labels = {
                  0,
                  widget.buckets.length - 1,
                  for (var index = stride;
                      index < widget.buckets.length - 1;
                      index += stride)
                    if (index * step >= 70 &&
                        (widget.buckets.length - 1 - index) * step >= 70)
                      index,
                };
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        key: Key('progress-${widget.keyPrefix}-lines'),
                        painter: ProgressLineChartPainter(
                          series: active,
                          colors: colors,
                          maximum: maximum,
                          gridColor:
                              Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    for (final tick in {
                      0,
                      for (var i = 1; i <= 4; i++) (maximum * i / 4).round(),
                    })
                      Positioned(
                        left: 0,
                        width: 40,
                        top: plot.bottom - tick / maximum * plot.height - 8,
                        child: Text(
                          format(tick),
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    for (final index in labels)
                      Positioned(
                        left: x(index) - 30,
                        width: 60,
                        bottom: 2,
                        child: Text(
                          calendarDate(widget.buckets[index].range.start)
                              .substring(5),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    for (var index = 0; index < widget.buckets.length; index++)
                      Positioned(
                        left: math.max(plot.left, x(index) - step / 2),
                        top: plot.top,
                        width: math.min(
                          step,
                          plot.right - math.max(plot.left, x(index) - step / 2),
                        ),
                        height: plot.height,
                        child: Tooltip(
                          message: '${widget.buckets[index].range.label}\n'
                              '${active.map((series) => '${series.label}: ${series.values[index] == null ? 'Not recorded' : format(series.values[index]!)}').join('\n')}',
                          child: Semantics(
                            button: true,
                            label: '${widget.buckets[index].range.label}. '
                                '${active.map((series) => '${series.label}: ${series.values[index] == null ? 'Not recorded' : format(series.values[index]!)}').join(', ')}. View workouts.',
                            child: InkWell(
                              key: Key('progress-${widget.keyPrefix}-$index'),
                              onTap: () => widget.onTap(
                                index,
                                active.map((series) => series.id).toSet(),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        if (widget.showLegend)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final series in widget.series)
                FilterChip(
                  key: Key('progress-grade-${series.id}'),
                  avatar: Icon(
                    Icons.show_chart,
                    color: colors[series.id],
                    size: 18,
                  ),
                  label: Text(
                    '${series.label} · ${series.values.whereType<int>().fold<int>(0, (sum, value) => sum + value)}',
                  ),
                  selected: !_excluded.contains(series.id),
                  onSelected: (include) => setState(() {
                    if (include) {
                      _excluded.remove(series.id);
                    } else {
                      _excluded.add(series.id);
                    }
                  }),
                ),
            ],
          ),
      ],
    );
  }
}

class ProgressLineChartPainter extends CustomPainter {
  ProgressLineChartPainter({
    required this.series,
    required this.colors,
    required this.maximum,
    required this.gridColor,
  });
  final List<ProgressLineSeries> series;
  final Map<String, Color> colors;
  final int maximum;
  final Color gridColor;

  static Rect plotRect(Size size) =>
      Rect.fromLTRB(48, 12, size.width - 32, size.height - 34);

  static const markerRadius = 3.5;

  Offset _pointFor(ProgressLineSeries line, int index, Size size) {
    final plot = plotRect(size);
    return Offset(
      line.values.length == 1
          ? plot.center.dx
          : plot.left + index / (line.values.length - 1) * plot.width,
      plot.bottom - line.values[index]! / maximum * plot.height,
    );
  }

  List<List<Offset>> segmentsFor(ProgressLineSeries line, Size size) {
    final result = <List<Offset>>[];
    List<Offset>? segment;
    for (var index = 0; index < line.values.length; index++) {
      final value = line.values[index];
      if (value == null) {
        segment = null;
        continue;
      }
      if (segment == null) {
        segment = [];
        result.add(segment);
      }
      segment.add(_pointFor(line, index, size));
    }
    return result;
  }

  Map<String, List<Offset?>> markerPositions(Size size) {
    final positions = {
      for (final line in series)
        line.id: [
          for (var index = 0; index < line.values.length; index++)
            line.values[index] == null ? null : _pointFor(line, index, size),
        ],
    };
    if (series.isEmpty) return positions;
    final plot = plotRect(size);
    final weeks = series.first.values.length;
    final step = weeks <= 1 ? plot.width : plot.width / (weeks - 1);
    for (var index = 0; index < weeks; index++) {
      final visible =
          series.where((line) => positions[line.id]![index] != null).toList()
            ..sort((a, b) {
              final order = positions[a.id]![index]!
                  .dy
                  .compareTo(positions[b.id]![index]!.dy);
              return order == 0 ? a.id.compareTo(b.id) : order;
            });
      for (var start = 0; start < visible.length;) {
        var end = start + 1;
        while (end < visible.length &&
            positions[visible[end].id]![index]!.dy -
                    positions[visible[end - 1].id]![index]!.dy <
                markerRadius * 2) {
          end++;
        }
        final count = end - start;
        if (count > 1) {
          // Keep displaced markers inside their week and the plot.
          final span = math.min(
            (count - 1) * markerRadius * 2,
            math.min(
              step *
                  (weeks > 1 && (index == 0 || index == weeks - 1) ? .4 : .8),
              plot.width,
            ),
          );
          final center = positions[visible[start].id]![index]!
              .dx
              .clamp(plot.left + span / 2, plot.right - span / 2);
          for (var rank = 0; rank < count; rank++) {
            final points = positions[visible[start + rank].id]!;
            points[index] = Offset(
              (center - span / 2 + rank * span / (count - 1))
                  .clamp(plot.left, plot.right),
              points[index]!.dy,
            );
          }
        }
        start = end;
      }
    }
    return positions;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotRect(size);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final tick in {
      0,
      for (var i = 1; i <= 4; i++) (maximum * i / 4).round(),
    }) {
      final y = plot.bottom - tick / maximum * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    for (final line in series) {
      final paint = Paint()
        ..color = colors[line.id]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      for (final segment in segmentsFor(line, size)) {
        final path = Path()..moveTo(segment.first.dx, segment.first.dy);
        for (final point in segment.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        if (segment.length > 1) {
          canvas.drawPath(path, paint);
        }
      }
    }
    final markers = markerPositions(size);
    for (final line in series) {
      for (final point in markers[line.id]!.whereType<Offset>()) {
        canvas.drawCircle(
          point,
          markerRadius,
          Paint()..color = colors[line.id]!,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ProgressLineChartPainter oldDelegate) => true;
}
