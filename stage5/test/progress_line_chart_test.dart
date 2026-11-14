import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/progress/presentation/progress_line_chart.dart';

void main() {
  ProgressLineChartPainter painter(ProgressLineSeries series) =>
      ProgressLineChartPainter(
        series: [series],
        colors: {series.id: Colors.blue},
        maximum: 4,
        gridColor: Colors.grey,
      );

  test('line segments connect recorded values but never bridge missing weeks',
      () {
    final series = ProgressLineSeries(
      id: 'grade',
      label: 'V4',
      values: [1, 2, null, 3, 4],
    );
    final plot = ProgressLineChartPainter.plotRect(const Size(400, 240));
    final segments = painter(series).segmentsFor(series, const Size(400, 240));
    expect(segments.map((segment) => segment.length).toList(), [2, 2]);
    expect(
      segments.first.first,
      Offset(plot.left, plot.bottom - plot.height / 4),
    );
    expect(segments.last.last, plot.topRight);
    expect(segments.first.last.dx, lessThan(segments.last.first.dx));
  });
  test('known zero stays on the line and a single week is centered', () {
    final series =
        ProgressLineSeries(id: 'volume', label: 'Climbs', values: [0]);
    final plot = ProgressLineChartPainter.plotRect(const Size(320, 240));
    expect(
      painter(series).segmentsFor(series, const Size(320, 240)).single.single,
      Offset(plot.center.dx, plot.bottom),
    );
  });
  test('zero connects adjacent observations but missing grades break the line',
      () {
    final volume =
        ProgressLineSeries(id: 'volume', label: 'Climbs', values: [2, 0, 3]);
    final grade =
        ProgressLineSeries(id: 'grade', label: 'Grade', values: [2, null, 3]);
    const size = Size(320, 240);
    final volumeSegments = painter(volume).segmentsFor(volume, size);
    expect(volumeSegments, hasLength(1));
    expect(volumeSegments.single, hasLength(3));
    expect(volumeSegments.single[1].dy,
        ProgressLineChartPainter.plotRect(size).bottom);
    expect(
        painter(grade).segmentsFor(grade, size).map((s) => s.length), [1, 1]);
  });

  ProgressLineChartPainter multiPainter(
    List<ProgressLineSeries> series, {
    int maximum = 4,
  }) =>
      ProgressLineChartPainter(
        series: series,
        colors: {for (final line in series) line.id: Colors.blue},
        maximum: maximum,
        gridColor: Colors.grey,
      );

  test('overlapping markers separate without changing lines or vertical values',
      () {
    const size = Size(320, 240);
    final lines = [
      for (final id in ['V6', 'V4', 'V5'])
        ProgressLineSeries(id: id, label: id, values: [2, 2, 2]),
    ];
    final chart = multiPainter(lines);
    final positions = chart.markerPositions(size);
    final plot = ProgressLineChartPainter.plotRect(size);
    for (var week = 0; week < 3; week++) {
      final actual = chart.segmentsFor(lines.first, size).single[week];
      final dots = [
        for (final id in ['V4', 'V5', 'V6']) positions[id]![week]!,
      ];
      expect(dots.map((point) => point.dy), everyElement(actual.dy));
      expect(dots[1].dx - dots[0].dx, 7);
      expect(dots[2].dx - dots[1].dx, 7);
      expect(dots.first.dx, greaterThanOrEqualTo(plot.left));
      expect(dots.last.dx, lessThanOrEqualTo(plot.right));
    }
    expect(positions['V5']![1]!.dx, plot.center.dx);
    expect(chart.segmentsFor(lines.first, size).single.first.dx, plot.left);
    expect(chart.segmentsFor(lines.first, size).single.last.dx, plot.right);
    expect(
      multiPainter(lines.reversed.toList()).markerPositions(size),
      positions,
    );
  });

  test(
      'only colliding markers move; missing points and known zeros are retained',
      () {
    const size = Size(320, 240);
    final lines = [
      ProgressLineSeries(id: 'a', label: 'a', values: [10, 0, null]),
      ProgressLineSeries(id: 'b', label: 'b', values: [11, 0, null]),
      ProgressLineSeries(id: 'c', label: 'c', values: [30, null, 20]),
    ];
    final chart = multiPainter(lines, maximum: 100);
    final positions = chart.markerPositions(size);
    expect(positions['a']![0]!.dx, isNot(positions['b']![0]!.dx));
    expect(
      positions['a']![0]!.dy,
      chart.segmentsFor(lines[0], size).single.first.dy,
    );
    expect(
      positions['b']![0]!.dy,
      chart.segmentsFor(lines[1], size).single.first.dy,
    );
    expect(positions['c']![0], chart.segmentsFor(lines[2], size).first.single);
    expect(positions['c']![2], chart.segmentsFor(lines[2], size).last.single);
    expect(positions['a']![2], isNull);
    expect(
        positions['a']![1]!.dy, ProgressLineChartPainter.plotRect(size).bottom);
    expect(positions['a']![1]!.dx, isNot(positions['b']![1]!.dx));
    final filtered = multiPainter([lines.first], maximum: 100);
    expect(filtered.markerPositions(size)['a']![0],
        filtered.segmentsFor(lines.first, size).single.first);
    expect(multiPainter([]).markerPositions(size), isEmpty);
  });

  test('single-week collisions center and dense weeks keep distinct positions',
      () {
    const size = Size(320, 240);
    final single = multiPainter([
      for (final id in ['a', 'b'])
        ProgressLineSeries(id: id, label: id, values: [1]),
    ]).markerPositions(size);
    final plot = ProgressLineChartPainter.plotRect(size);
    expect(single['a']!.single!.dx, plot.center.dx - 3.5);
    expect(single['b']!.single!.dx, plot.center.dx + 3.5);
    final dense = multiPainter([
      for (var grade = 0; grade < 20; grade++)
        ProgressLineSeries(
          id: '$grade',
          label: '$grade',
          values: List.filled(53, 1),
        ),
    ]).markerPositions(size);
    final step = plot.width / 52;
    for (var week = 0; week < 53; week++) {
      final xs = dense.values.map((points) => points[week]!.dx).toList()
        ..sort();
      expect(xs.toSet(), hasLength(20));
      expect(xs.last - xs.first,
          closeTo(step * (week == 0 || week == 52 ? .4 : .8), .00001));
      expect(xs.first, greaterThanOrEqualTo(plot.left));
      expect(xs.last, lessThanOrEqualTo(plot.right));
      final x = plot.left + week * step;
      expect(xs.first, greaterThan(x - step / 2));
      expect(xs.last, lessThan(x + step / 2));
    }
  });

  Future<void> pump(
    WidgetTester tester, {
    List<int?> values = const [1, 2, 3, 4, 2],
    bool legend = false,
    ValueChanged<int>? onTap,
    ProgressRange? range,
    ProgressInterval interval = ProgressInterval.week,
  }) async {
    final selectedRange = range ??
        ProgressRange(start: DateTime(2026, 10, 9), end: DateTime(2026, 11, 7));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ProgressLineChart(
              keyPrefix: 'test',
              buckets:
                  ClimbingProgressReport(range: selectedRange, sessions: [])
                      .bucketsFor(interval),
              interval: interval,
              series: [
                ProgressLineSeries(id: 'V4', label: 'V4', values: values),
              ],
              showLegend: legend,
              onTap: (index, _) => onTap?.call(index),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'renders stroked lines, keeps phone width, and opens the selected week',
      (tester) async {
    int? tapped;
    await pump(tester, onTap: (index) => tapped = index);
    expect(
      find.byKey(const Key('progress-test-lines')),
      paints..path(strokeWidth: 2.5, style: PaintingStyle.stroke),
    );
    await tester.tap(find.byKey(const Key('progress-test-3')));
    expect(tapped, 3);
    expect(
      tester.getSize(find.byKey(const Key('progress-test-lines'))).width,
      320,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'grade toggles have a recoverable empty selection and explicit missing data',
      (tester) async {
    await pump(tester, legend: true);
    await tester.tap(find.byKey(const Key('progress-grade-V4')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a grade to show its line.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('progress-grade-V4')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('progress-test-lines')), findsOneWidget);
    await pump(tester, values: [null, null, null, null, null]);
    expect(find.text('No recorded data in this range.'), findsOneWidget);
    expect(find.byKey(const Key('progress-test-lines')), findsNothing);
  });
  testWidgets('a full year fits phone width with readable date ticks',
      (tester) async {
    final range = ProgressPreset.year.range(DateTime(2026, 11, 7));
    final weeks =
        ClimbingProgressReport(range: range, sessions: []).weeklyBuckets;
    await pump(tester, range: range, values: List.filled(weeks.length, 3));
    expect(
      tester.getSize(find.byKey(const Key('progress-test-lines'))).width,
      320,
    );
    final dates = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data != null &&
          RegExp(r'^\d{2}-\d{2}$').hasMatch(widget.data!),
    );
    expect(dates.evaluate().length, lessThanOrEqualTo(5));
    final chart = tester.getRect(find.byKey(const Key('progress-test-lines')));
    for (final element in dates.evaluate()) {
      final label = tester.getRect(find.byWidget(element.widget));
      expect(label.left, greaterThanOrEqualTo(chart.left));
      expect(label.right, lessThanOrEqualTo(chart.right));
    }
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('malformed series fail explicitly', (tester) async {
    await pump(tester, values: [1]);
    expect(tester.takeException(), isA<StateError>());
    await pump(tester, values: [1, 2, -1, 2, 1]);
    expect(tester.takeException(), isA<StateError>());
  });
  testWidgets('daily year data fits phone width with readable date ticks',
      (tester) async {
    final range =
        ProgressRange(start: DateTime(2024), end: DateTime(2024, 12, 31));
    await pump(tester,
        range: range,
        interval: ProgressInterval.day,
        values: List.filled(366, 1));
    expect(tester.getSize(find.byKey(const Key('progress-test-lines'))).width,
        320);
    expect(find.byType(SingleChildScrollView), findsNothing);
    final dates = find.byWidgetPredicate((widget) =>
        widget is Text &&
        widget.data != null &&
        RegExp(r'^\d{2}-\d{2}$').hasMatch(widget.data!));
    expect(dates.evaluate().length, lessThanOrEqualTo(5));
    await tester.tap(find.byKey(const Key('progress-test-365')));
    expect(tester.takeException(), isNull);
  });
  testWidgets('month and year ticks distinguish calendar years',
      (tester) async {
    final range =
        ProgressRange(start: DateTime(2025, 12, 15), end: DateTime(2026, 2, 1));
    await pump(tester,
        range: range, interval: ProgressInterval.month, values: [1, 2, 3]);
    for (final label in ['2025-12', '2026-01', '2026-02']) {
      expect(find.text(label), findsOneWidget);
    }
    await pump(tester,
        range: range, interval: ProgressInterval.year, values: [1, 2]);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('point drill-down identifies only visible grade lines',
      (tester) async {
    Set<String>? visible;
    final range = ProgressPreset.month.range(DateTime(2026, 11, 7));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressLineChart(
            keyPrefix: 'test',
            buckets: ClimbingProgressReport(range: range, sessions: [])
                .weeklyBuckets,
            series: [
              ProgressLineSeries(
                id: 'V4',
                label: 'V4',
                values: [1, 2, 3, 2, 1],
              ),
              ProgressLineSeries(
                id: 'V6',
                label: 'V6',
                values: [1, 2, 3, 2, 1],
              ),
            ],
            showLegend: true,
            onTap: (_, ids) => visible = ids,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chart = tester
        .widget<CustomPaint>(
          find.byKey(const Key('progress-test-lines')),
        )
        .painter! as ProgressLineChartPainter;
    final size = tester.getSize(find.byKey(const Key('progress-test-lines')));
    final markers = chart.markerPositions(size);
    expect(markers['V4']![3]!.dx, isNot(markers['V6']![3]!.dx));
    final tooltip = tester.widget<Tooltip>(find.ancestor(
      of: find.byKey(const Key('progress-test-3')),
      matching: find.byType(Tooltip),
    ));
    expect(tooltip.message, contains('V4: 2\nV6: 2'));
    final painting = paints
      ..path(strokeWidth: 2.5)
      ..path(strokeWidth: 2.5);
    for (final id in ['V4', 'V6']) {
      for (final point in markers[id]!) {
        painting.circle(
          x: point!.dx,
          y: point.dy,
          radius: 3.5,
          color: chart.colors[id],
        );
      }
    }
    expect(find.byKey(const Key('progress-test-lines')), painting);
    await tester.tap(find.byKey(const Key('progress-grade-V4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('progress-test-3')));
    expect(visible, {'V6'});
  });
}
