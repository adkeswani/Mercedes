import 'package:flutter_test/flutter_test.dart';
import 'package:stage4/core/enums.dart';
import 'package:stage4/features/load/domain/load_model.dart';

void main() {
  group('DefaultLoadStrategy.effortFromRpe', () {
    test('RPE 1 → effort 1', () {
      expect(DefaultLoadStrategy.effortFromRpe(1), 1);
    });

    test('RPE 2 → effort 1', () {
      expect(DefaultLoadStrategy.effortFromRpe(2), 1);
    });

    test('RPE 3 → effort 2', () {
      expect(DefaultLoadStrategy.effortFromRpe(3), 2);
    });

    test('RPE 4 → effort 2', () {
      expect(DefaultLoadStrategy.effortFromRpe(4), 2);
    });

    test('RPE 5 → effort 3', () {
      expect(DefaultLoadStrategy.effortFromRpe(5), 3);
    });

    test('RPE 6 → effort 3', () {
      expect(DefaultLoadStrategy.effortFromRpe(6), 3);
    });

    test('RPE 7 → effort 4', () {
      expect(DefaultLoadStrategy.effortFromRpe(7), 4);
    });

    test('RPE 8 → effort 4', () {
      expect(DefaultLoadStrategy.effortFromRpe(8), 4);
    });

    test('RPE 9 → effort 5', () {
      expect(DefaultLoadStrategy.effortFromRpe(9), 5);
    });

    test('RPE 10 → effort 5', () {
      expect(DefaultLoadStrategy.effortFromRpe(10), 5);
    });

    test('throws on RPE 0', () {
      expect(
        () => DefaultLoadStrategy.effortFromRpe(0),
        throwsArgumentError,
      );
    });

    test('throws on RPE 11', () {
      expect(
        () => DefaultLoadStrategy.effortFromRpe(11),
        throwsArgumentError,
      );
    });
  });

  group('DefaultLoadStrategy.durationModifier', () {
    test('< 30 min → 0.75', () {
      expect(DefaultLoadStrategy.durationModifier(0), 0.75);
      expect(DefaultLoadStrategy.durationModifier(15), 0.75);
      expect(DefaultLoadStrategy.durationModifier(29), 0.75);
    });

    test('30-75 min → 1.0', () {
      expect(DefaultLoadStrategy.durationModifier(30), 1.0);
      expect(DefaultLoadStrategy.durationModifier(50), 1.0);
      expect(DefaultLoadStrategy.durationModifier(75), 1.0);
    });

    test('> 75 min → 1.25', () {
      expect(DefaultLoadStrategy.durationModifier(76), 1.25);
      expect(DefaultLoadStrategy.durationModifier(120), 1.25);
    });

    test('throws on negative duration', () {
      expect(
        () => DefaultLoadStrategy.durationModifier(-1),
        throwsArgumentError,
      );
    });
  });

  group('LoadModel.typeWeights', () {
    test('all workout types have weights', () {
      for (final type in WorkoutType.values) {
        expect(
          LoadModel.typeWeights.containsKey(type),
          isTrue,
          reason: 'Missing weight for $type',
        );
      }
    });

    test('climbing type weights match spec', () {
      expect(LoadModel.typeWeights[WorkoutType.limit], 5);
      expect(LoadModel.typeWeights[WorkoutType.power], 4);
      expect(LoadModel.typeWeights[WorkoutType.powerEndurance], 4);
      expect(LoadModel.typeWeights[WorkoutType.endurance], 2);
      expect(LoadModel.typeWeights[WorkoutType.skill], 2);
      expect(LoadModel.typeWeights[WorkoutType.cardio], 2);
      expect(LoadModel.typeWeights[WorkoutType.mobility], 1);
    });

    test('strength type weights match spec', () {
      expect(LoadModel.typeWeights[WorkoutType.lower], 4);
      expect(LoadModel.typeWeights[WorkoutType.legs], 4);
      expect(LoadModel.typeWeights[WorkoutType.upper], 3);
      expect(LoadModel.typeWeights[WorkoutType.fullBody], 3);
      expect(LoadModel.typeWeights[WorkoutType.push], 3);
      expect(LoadModel.typeWeights[WorkoutType.pull], 3);
      expect(LoadModel.typeWeights[WorkoutType.core], 2);
      expect(LoadModel.typeWeights[WorkoutType.conditioning], 2);
    });
  });

  group('LoadModel.computeLoadPoints', () {
    test('limit RPE 9, 60 min → 5 × 5 × 1.0 = 25.0', () {
      final result = LoadModel.computeLoadPoints(
        workoutType: WorkoutType.limit,
        rpe: 9,
        durationMinutes: 60,
      );
      expect(result, 25.0);
    });

    test('mobility RPE 2, 20 min → 1 × 1 × 0.75 = 0.75', () {
      final result = LoadModel.computeLoadPoints(
        workoutType: WorkoutType.mobility,
        rpe: 2,
        durationMinutes: 20,
      );
      expect(result, 0.75);
    });

    test('pull RPE 7, 45 min → 3 × 4 × 1.0 = 12.0', () {
      final result = LoadModel.computeLoadPoints(
        workoutType: WorkoutType.pull,
        rpe: 7,
        durationMinutes: 45,
      );
      expect(result, 12.0);
    });

    test('power RPE 10, 90 min → 4 × 5 × 1.25 = 25.0', () {
      final result = LoadModel.computeLoadPoints(
        workoutType: WorkoutType.power,
        rpe: 10,
        durationMinutes: 90,
      );
      expect(result, 25.0);
    });

    test('endurance RPE 5, 15 min → 2 × 3 × 0.75 = 4.5', () {
      final result = LoadModel.computeLoadPoints(
        workoutType: WorkoutType.endurance,
        rpe: 5,
        durationMinutes: 15,
      );
      expect(result, 4.5);
    });

    test('core RPE 6, 30 min → 2 × 3 × 1.0 = 6.0', () {
      final result = LoadModel.computeLoadPoints(
        workoutType: WorkoutType.core,
        rpe: 6,
        durationMinutes: 30,
      );
      expect(result, 6.0);
    });
  });

  group('LoadModel.categorize', () {
    test('easy ≤ 6', () {
      expect(LoadModel.categorize(0), LoadBucket.easy);
      expect(LoadModel.categorize(3.5), LoadBucket.easy);
      expect(LoadModel.categorize(6.0), LoadBucket.easy);
    });

    test('medium 7–12', () {
      expect(LoadModel.categorize(6.1), LoadBucket.medium);
      expect(LoadModel.categorize(9.0), LoadBucket.medium);
      expect(LoadModel.categorize(12.0), LoadBucket.medium);
    });

    test('hard ≥ 13', () {
      expect(LoadModel.categorize(12.1), LoadBucket.hard);
      expect(LoadModel.categorize(25.0), LoadBucket.hard);
    });
  });

  group('LoadModel.currentVersion', () {
    test('is 1', () {
      expect(LoadModel.currentVersion, 1);
    });
  });

  group('Per-program type weight overrides', () {
    test('override changes computed load', () {
      // Default power weight = 4
      final defaultResult = LoadModel.computeLoadPoints(
        workoutType: WorkoutType.power,
        rpe: 5,
        durationMinutes: 60,
      );
      // 4 × 3 × 1.0 = 12.0
      expect(defaultResult, 12.0);

      // Override power weight to 2
      final overrideResult = LoadModel.computeLoadPoints(
        workoutType: WorkoutType.power,
        rpe: 5,
        durationMinutes: 60,
        typeWeightOverrides: {WorkoutType.power: 2},
      );
      // 2 × 3 × 1.0 = 6.0
      expect(overrideResult, 6.0);
    });

    test('override only affects specified types', () {
      // Override power but compute for pull (should use default pull = 3)
      final result = LoadModel.computeLoadPoints(
        workoutType: WorkoutType.pull,
        rpe: 7,
        durationMinutes: 45,
        typeWeightOverrides: {WorkoutType.power: 2},
      );
      // 3 × 4 × 1.0 = 12.0 (pull default unchanged)
      expect(result, 12.0);
    });

    test('validateTypeWeightOverrides accepts valid overrides', () {
      expect(
        () => LoadModel.validateTypeWeightOverrides({
          WorkoutType.power: 3,
          WorkoutType.limit: 6,
        }),
        returnsNormally,
      );
    });

    test('validateTypeWeightOverrides rejects zero weight', () {
      expect(
        () => LoadModel.validateTypeWeightOverrides({
          WorkoutType.power: 0,
        }),
        throwsArgumentError,
      );
    });

    test('validateTypeWeightOverrides rejects negative weight', () {
      expect(
        () => LoadModel.validateTypeWeightOverrides({
          WorkoutType.power: -1,
        }),
        throwsArgumentError,
      );
    });
  });

  group('Custom LoadStrategy', () {
    test('custom strategy is used when provided', () {
      final custom = _DoubleWeightStrategy();

      final result = LoadModel.computeLoadPoints(
        workoutType: WorkoutType.pull,
        rpe: 7,
        durationMinutes: 45,
        strategy: custom,
      );
      // Default pull = 3, doubled = 6; 6 × 4 × 1.0 = 24.0
      expect(result, 24.0);
    });

    test('custom strategy categorize is used when provided', () {
      final custom = _DoubleWeightStrategy();

      // Custom: everything ≤ 10 is easy
      expect(
        LoadModel.categorize(8.0, strategy: custom),
        LoadBucket.easy,
      );
      // Default would say medium for 8.0
      expect(LoadModel.categorize(8.0), LoadBucket.medium);
    });

    test('DefaultLoadStrategy has correct name and version', () {
      const strategy = DefaultLoadStrategy();
      expect(strategy.name, 'default_v1');
      expect(strategy.version, 1);
    });
  });

  group('DefaultLoadStrategy.resolveTypeWeight', () {
    test('returns default when no overrides', () {
      final weight = DefaultLoadStrategy.resolveTypeWeight(
        WorkoutType.power,
        null,
      );
      expect(weight, 4);
    });

    test('returns override when present', () {
      final weight = DefaultLoadStrategy.resolveTypeWeight(
        WorkoutType.power,
        {WorkoutType.power: 2},
      );
      expect(weight, 2);
    });

    test('returns default for types not in override map', () {
      final weight = DefaultLoadStrategy.resolveTypeWeight(
        WorkoutType.pull,
        {WorkoutType.power: 2},
      );
      expect(weight, 3);
    });
  });
}

/// Test strategy that doubles default type weights.
class _DoubleWeightStrategy implements LoadStrategy {
  @override
  int get version => 99;

  @override
  String get name => 'double_test';

  @override
  double computeLoadPoints({
    required WorkoutType workoutType,
    required int rpe,
    required int durationMinutes,
    Map<WorkoutType, int>? typeWeightOverrides,
  }) {
    final baseWeight =
        DefaultLoadStrategy.defaultTypeWeights[workoutType] ?? 1;
    final doubled = baseWeight * 2;
    final effort = DefaultLoadStrategy.effortFromRpe(rpe);
    final durMod = DefaultLoadStrategy.durationModifier(durationMinutes);

    return doubled * effort * durMod;
  }

  @override
  LoadBucket categorize(double loadPoints) {
    // More lenient thresholds for testing
    if (loadPoints <= 10) {
      return LoadBucket.easy;
    } else if (loadPoints <= 20) {
      return LoadBucket.medium;
    } else {
      return LoadBucket.hard;
    }
  }
}
