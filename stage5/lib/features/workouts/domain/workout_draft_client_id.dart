import 'dart:math';

typedef WorkoutDraftClock = DateTime Function();
typedef WorkoutDraftRandomInt = int Function(int max);

class WorkoutDraftClientIdGenerator {
  WorkoutDraftClientIdGenerator({
    WorkoutDraftClock? clock,
    WorkoutDraftRandomInt? randomInt,
  })  : _clock = clock ?? DateTime.now,
        _randomInt = randomInt ?? Random.secure().nextInt;

  static const randomByteCount = 16;
  static final _validPattern = RegExp(r'^[0-9a-f]+-[0-9a-f]{32}$');

  final WorkoutDraftClock _clock;
  final WorkoutDraftRandomInt _randomInt;

  String generate() {
    final timestamp = _clock().toUtc().microsecondsSinceEpoch.toRadixString(16);
    final randomHex = List.generate(
      randomByteCount,
      (_) => _randomInt(256).toRadixString(16).padLeft(2, '0'),
      growable: false,
    ).join();
    return '$timestamp-$randomHex';
  }

  static bool isValid(String value) {
    return value.length <= 128 && _validPattern.hasMatch(value);
  }
}
