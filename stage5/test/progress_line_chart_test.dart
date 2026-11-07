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

  Future<void> pump(
    WidgetTester tester, {
    List<int?> values = const [1, 2, 3, 4, 2],
    bool legend = false,
    ValueChanged<int>? onTap,
    ProgressRange? range,
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
                      .weeklyBuckets,
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
                values: [0, 1, 0, 1, 0],
              ),
            ],
            showLegend: true,
            onTap: (_, ids) => visible = ids,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('progress-grade-V4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('progress-test-3')));
    expect(visible, {'V6'});
  });
}
