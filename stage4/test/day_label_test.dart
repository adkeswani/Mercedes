import 'package:flutter_test/flutter_test.dart';
import 'package:stage4/features/programs/presentation/program_builder_screen.dart';

void main() {
  group('dayLabel', () {
    test('offset 0 is Day 1 (program start date)', () {
      expect(dayLabel(0), 'Day 1');
    });

    test('offset maps to Day N+1', () {
      expect(dayLabel(1), 'Day 2');
      expect(dayLabel(6), 'Day 7');
      expect(dayLabel(7), 'Day 8');
      expect(dayLabel(13), 'Day 14');
    });
  });
}
