import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/routing/router.dart';
import 'package:stage5/features/auth/data/user_profile_repository.dart';
import 'package:stage5/features/auth/domain/user_profile.dart';
import 'package:stage5/features/auth/presentation/app_entry_providers.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';

void main() {
  test(
      'same UID refresh retains profile, backfill, and router; logout changes it',
      () async {
    final auth = StreamController<User?>();
    final profiles = _Profiles();
    var backfills = 0;
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => auth.stream),
      userProfileRepositoryProvider.overrideWithValue(profiles),
      exerciseVersionBackfillForUserProvider.overrideWith((ref, uid) async {
        backfills++;
        return 0;
      }),
    ]);
    addTearDown(() async {
      container.dispose();
      await auth.close();
    });
    final states = <AppEntryState>[];
    container.listen(appEntryStateProvider, (_, next) => states.add(next));
    final signedIn = container.read(authStateProvider.future);
    auth.add(_User('athlete-1'));
    await signedIn;
    await container.read(userProfileProvider.future);
    await container.read(exerciseVersionBackfillProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(appEntryStateProvider), AppEntryState.ready);
    final router = container.read(routerProvider);
    states.clear();

    auth.add(_User('athlete-1'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(routerProvider), same(router));
    expect(profiles.reads, ['athlete-1']);
    expect(backfills, 1);
    expect(states, isEmpty);

    auth.add(_User('athlete-2'));
    await Future<void>.delayed(Duration.zero);
    await container.read(userProfileProvider.future);
    await container.read(exerciseVersionBackfillProvider.future);
    expect(profiles.reads, ['athlete-1', 'athlete-2']);
    expect(backfills, 2);
    auth.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(appEntryStateProvider), AppEntryState.signedOut);
    expect(container.read(routerProvider), isNot(same(router)));
  });
}

class _User extends Fake implements User {
  _User(this.uid);

  @override
  final String uid;
}

class _Profiles extends Fake implements UserProfileRepository {
  final reads = <String>[];

  @override
  Stream<UserProfile?> watchUserProfile(String uid) {
    reads.add(uid);
    return Stream.value(UserProfile(
      uid: uid,
      displayName: 'Athlete',
      email: 'athlete@example.test',
      username: uid,
      createdAt: DateTime.utc(2026),
      createdBy: uid,
      updatedAt: DateTime.utc(2026),
      updatedBy: uid,
    ));
  }
}
