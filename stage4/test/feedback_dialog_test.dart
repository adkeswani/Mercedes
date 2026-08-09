import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/profile/presentation/feedback_dialog.dart';

void main() {
  testWidgets('submits selected feedback and closes', (tester) async {
    FeedbackType? submittedType;
    String? submittedBody;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => FeedbackDialog(
                onSubmit: (type, body) async {
                  submittedType = type;
                  submittedBody = body;
                },
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      '  The calendar is easy to use.  ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(submittedType, FeedbackType.general);
    expect(submittedBody, 'The calendar is easy to use.');
    expect(find.text('Send feedback'), findsNothing);
  });

  testWidgets('requires a feedback message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackDialog(onSubmit: (_, __) async {}),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();

    expect(find.text('Enter your feedback'), findsOneWidget);
  });
}
