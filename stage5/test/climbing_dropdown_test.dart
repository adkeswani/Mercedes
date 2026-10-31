import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/presentation/climbing_grade_field.dart';

import '../integration_test/support/dropdown_test_utils.dart';

void main() {
  setUp(() {
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previous);
  });
  testWidgets('reveals virtualized YDS grades in both directions',
      (tester) async {
    tester.view.physicalSize = const Size(600, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var grade = '5.0';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(builder: (context, setState) {
            return Column(children: [
              const Text('5.13a'),
              ClimbingGradeField(
                system: ClimbingGradingSystem.yds,
                grade: grade,
                onChanged: (_, value) => setState(() => grade = value),
              ),
            ]);
          }),
        ),
      ),
    ));
    final field = find.byType(DropdownButtonFormField<String>);
    await tester.tap(field);
    await tester.pump(const Duration(milliseconds: 400));
    final popup = find.byType(Scrollable).last;
    expect(
      find.descendant(of: popup, matching: find.text('5.13a')),
      findsNothing,
    );
    await tester.tap(await revealDropdownOption(tester, field, '5.13a'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(grade, '5.13a');
    await tester.tap(field);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(await revealDropdownOption(tester, field, '5.0'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(grade, '5.0');
  });

  testWidgets('reveals a virtualized optional row RPE', (tester) async {
    tester.view.physicalSize = const Size(600, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? recorded;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DropdownButtonFormField<int>(
          items: [
            const DropdownMenuItem<int>(
                value: null, child: Text('Not recorded')),
            for (var i = 1; i <= 10; i++)
              DropdownMenuItem(value: i, child: Text('$i')),
          ],
          onChanged: (value) => recorded = value,
        ),
      ),
    ));
    final field = find.byType(DropdownButtonFormField<int>);
    await tester.tap(field);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(await revealDropdownOption(tester, field, 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(recorded, 10);
  });

  testWidgets('popup target stays scoped when a sidebar follows its navigator',
      (tester) async {
    tester.view.physicalSize = const Size(600, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var grade = '5.0';
    final sidebar = ScrollController();
    addTearDown(sidebar.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Row(children: [
        Expanded(
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: SingleChildScrollView(
                  child: StatefulBuilder(builder: (_, setState) {
                    return ClimbingGradeField(
                      system: ClimbingGradingSystem.yds,
                      grade: grade,
                      onChanged: (_, value) => setState(() => grade = value),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 120,
          child: ListView(
            key: const Key('sidebar'),
            controller: sidebar,
            children: const [
              Text('5.13a'),
              SizedBox(height: 2000),
            ],
          ),
        ),
      ]),
    ));
    final field = find.byType(DropdownButtonFormField<String>);
    await tester.tap(field);
    await tester.pump(const Duration(milliseconds: 400));
    final sidebarScrollable = find.descendant(
      of: find.byKey(const Key('sidebar')),
      matching: find.byType(Scrollable),
    );
    expect(find.byType(Scrollable).last.evaluate().single,
        same(sidebarScrollable.evaluate().single));
    final target = await revealDropdownOption(tester, field, '5.13a');
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 400));
    expect(grade, '5.13a');
    expect(sidebar.offset, 0);
  });
}
