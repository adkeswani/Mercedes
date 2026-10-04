import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/workouts/domain/workout_draft_client_id.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';

void main() {
  test('generates a timestamped 128-bit ID using web-safe byte bounds', () {
    final fixedTime = DateTime.utc(2026, 10, 4, 21, 10);
    final bounds = <int>[];
    var nextByte = 0;
    final generator = WorkoutDraftClientIdGenerator(
      clock: () => fixedTime,
      randomInt: (max) {
        bounds.add(max);
        return nextByte++;
      },
    );

    final id = generator.generate();

    expect(
      id,
      '${fixedTime.microsecondsSinceEpoch.toRadixString(16)}-'
      '000102030405060708090a0b0c0d0e0f',
    );
    expect(bounds, hasLength(WorkoutDraftClientIdGenerator.randomByteCount));
    expect(bounds, everyElement(256));
  });

  test('client ID provider creates one stable session ID per container', () {
    final fixedTime = DateTime.utc(2026, 10, 4, 21, 10);
    final container = ProviderContainer(
      overrides: [
        workoutDraftClientIdGeneratorProvider.overrideWithValue(
          WorkoutDraftClientIdGenerator(
            clock: () => fixedTime,
            randomInt: (_) => 0xab,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final first = container.read(workoutDraftClientIdProvider);
    final second = container.read(workoutDraftClientIdProvider);

    expect(second, first);
    expect(first, matches(RegExp(r'^[0-9a-f]+-[0-9a-f]{32}$')));
    expect(first.length, lessThanOrEqualTo(128));
  });
}
