import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/features/exercises/presentation/youtube_embed.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/presentation/climbing_grade_field.dart';
import 'package:web/web.dart' as web;

import 'dropdown_test_utils.dart';

void registerYoutubePointerTest() {
  testWidgets('climbing dropdown blocks input to the native video underneath',
      (tester) async {
    var system = ClimbingGradingSystem.vScale;
    var grade = 'V0';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return Column(children: [
            ClimbingGradeField(
              system: system,
              grade: grade,
              onChanged: (nextSystem, nextGrade) => setState(() {
                system = nextSystem;
                grade = nextGrade;
              }),
            ),
            SizedBox(width: 400, child: buildYoutubeEmbed('aaaaaaaaaaa')),
          ]);
        }),
      ),
    ));
    await tester.pumpAndSettle();
    final iframe = web.document.querySelector(
            'iframe[src="https://www.youtube.com/embed/aaaaaaaaaaa"]')
        as web.HTMLIFrameElement;
    expect(iframe.style.pointerEvents, 'auto');
    final field = find.byType(DropdownButtonFormField<String>);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(iframe.style.pointerEvents, 'none');
    await tester.tap(await revealDropdownOption(tester, field, 'V2'));
    await tester.pumpAndSettle();
    expect(grade, 'V2');
    expect(iframe.style.pointerEvents, 'auto');
    expect(
        web.document.querySelector(
            'iframe[src="https://www.youtube.com/embed/aaaaaaaaaaa"]'),
        same(iframe),
        reason: 'Opening a popup must not recreate or reload the player');
  });
}
