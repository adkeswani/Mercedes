import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/features/exercises/presentation/youtube_embed.dart';

void main() {
  testWidgets('video input is disabled until a dropdown closes',
      (tester) async {
    var interactive = true;
    var selected = 1;
    var videoTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            DropdownButtonFormField<int>(
              initialValue: selected,
              items: const [
                DropdownMenuItem(value: 1, child: Text('First')),
                DropdownMenuItem(value: 2, child: Text('Second')),
              ],
              onChanged: (value) => selected = value!,
            ),
            YoutubeEmbedInteraction(builder: (enabled) {
              interactive = enabled;
              return IgnorePointer(
                ignoring: !enabled,
                child: TextButton(
                  onPressed: () => videoTaps++,
                  child: const Text('Video'),
                ),
              );
            }),
          ],
        ),
      ),
    ));
    expect(interactive, isTrue);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(interactive, isFalse);
    await tester.tap(find.text('Second').last);
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(videoTaps, 0);
    expect(interactive, isTrue);
    await tester.tap(find.text('Video'));
    expect(videoTaps, 1);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(interactive, isFalse);
    await tester.tapAt(const Offset(750, 550));
    await tester.pumpAndSettle();
    expect(interactive, isTrue);
    expect(videoTaps, 1);
  });
}
