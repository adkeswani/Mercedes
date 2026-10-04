import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/workouts/data/workout_draft_client_id_store_contract.dart';
import 'package:stage5/features/workouts/data/workout_draft_client_session.dart';
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

  test('new provider containers reuse the same tab session ID', () {
    final fixedTime = DateTime.utc(2026, 10, 4, 21, 10);
    final store = _MemoryClientIdStore();
    var nextByte = 0;
    final generator = WorkoutDraftClientIdGenerator(
      clock: () => fixedTime,
      randomInt: (_) => nextByte++,
    );
    final firstContainer = ProviderContainer(
      overrides: [
        workoutDraftClientIdStoreProvider.overrideWithValue(store),
        workoutDraftClientIdGeneratorProvider.overrideWithValue(generator),
      ],
    );

    final first = firstContainer.read(workoutDraftClientIdProvider);
    firstContainer.dispose();
    final recreatedContainer = ProviderContainer(
      overrides: [
        workoutDraftClientIdStoreProvider.overrideWithValue(store),
        workoutDraftClientIdGeneratorProvider.overrideWithValue(generator),
      ],
    );
    addTearDown(recreatedContainer.dispose);
    final recreated = recreatedContainer.read(workoutDraftClientIdProvider);

    expect(recreated, first);
    expect(first, matches(RegExp(r'^[0-9a-f]+-[0-9a-f]{32}$')));
    expect(first.length, lessThanOrEqualTo(128));
    expect(nextByte, WorkoutDraftClientIdGenerator.randomByteCount);
  });

  test('separate tab stores receive distinct client IDs', () {
    var nextByte = 0;
    final generator = WorkoutDraftClientIdGenerator(
      clock: () => DateTime.utc(2026, 10, 4, 21, 10),
      randomInt: (_) => nextByte++,
    );

    final first = WorkoutDraftClientSession(
      store: _MemoryClientIdStore(),
      generator: generator,
    ).getOrCreateClientId();
    final second = WorkoutDraftClientSession(
      store: _MemoryClientIdStore(),
      generator: generator,
    ).getOrCreateClientId();

    expect(second, isNot(first));
  });

  test('malformed stored ID is regenerated and overwritten', () {
    final store = _MemoryClientIdStore('athlete-identity-is-not-a-client-id');
    final session = WorkoutDraftClientSession(
      store: store,
      generator: WorkoutDraftClientIdGenerator(
        clock: () => DateTime.utc(2026, 10, 4, 21, 10),
        randomInt: (_) => 0xab,
      ),
    );

    final clientId = session.getOrCreateClientId();

    expect(clientId, matches(RegExp(r'^[0-9a-f]+-[0-9a-f]{32}$')));
    expect(store.value, clientId);
  });

  test('client ID storage errors remain explicit', () {
    final session = WorkoutDraftClientSession(
      store: _ThrowingClientIdStore(),
      generator: WorkoutDraftClientIdGenerator(
        randomInt: (_) => 0xab,
      ),
    );

    expect(session.getOrCreateClientId, throwsA(isA<StateError>()));
  });

  test('cached store survives root recreation when persistence disappears', () {
    var persisted = '19a00000000000-00112233445566778899aabbccddeeff';
    var reads = 0;
    final store = CachedWorkoutDraftClientIdStore(
      readPersisted: () {
        reads++;
        return persisted;
      },
      writePersisted: (clientId) => persisted = clientId,
    );

    expect(store.read(), persisted);
    persisted = '';

    expect(store.read(), '19a00000000000-00112233445566778899aabbccddeeff');
    expect(reads, 1);
  });

  test('cached store exposes write failures without caching the value', () {
    var shouldFail = true;
    var persisted = 'original';
    var reads = 0;
    final store = CachedWorkoutDraftClientIdStore(
      readPersisted: () {
        reads++;
        return persisted;
      },
      writePersisted: (clientId) {
        if (shouldFail) {
          throw StateError('session storage unavailable');
        }
        persisted = clientId;
      },
    );

    expect(() => store.write('replacement'), throwsStateError);
    shouldFail = false;
    persisted = 'reloaded';
    expect(store.read(), 'reloaded');
    expect(reads, 1);
  });
}

class _MemoryClientIdStore implements WorkoutDraftClientIdStore {
  _MemoryClientIdStore([this.value]);

  String? value;

  @override
  String? read() => value;

  @override
  void write(String clientId) {
    value = clientId;
  }
}

class _ThrowingClientIdStore implements WorkoutDraftClientIdStore {
  @override
  String? read() => throw StateError('session storage unavailable');

  @override
  void write(String clientId) =>
      throw StateError('session storage unavailable');
}
