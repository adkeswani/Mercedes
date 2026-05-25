import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage3/features/auth/data/user_profile_repository.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late UserProfileRepository repo;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repo = UserProfileRepository(firestore: fakeFirestore);
  });

  group('UserProfileRepository', () {
    group('getUserByUsername', () {
      test('returns profile when username exists', () async {
        // Set up user doc and username reservation
        await fakeFirestore.collection('users').doc('uid1').set({
          'uid': 'uid1',
          'displayName': 'Alice',
          'email': 'alice@example.com',
          'username': 'alice',
          'discoverable': false,
          'createdBy': 'system',
          'createdAt': DateTime(2024, 1, 1),
          'updatedAt': DateTime(2024, 1, 1),
          'updatedBy': 'system',
        });
        await fakeFirestore.collection('usernames').doc('alice').set({
          'uid': 'uid1',
        });

        final profile = await repo.getUserByUsername('alice');
        expect(profile, isNotNull);
        expect(profile!.uid, 'uid1');
        expect(profile.displayName, 'Alice');
      });

      test('returns null for non-existent username', () async {
        final profile = await repo.getUserByUsername('nobody');
        expect(profile, isNull);
      });

      test('normalizes username to lowercase', () async {
        await fakeFirestore.collection('users').doc('uid1').set({
          'uid': 'uid1',
          'displayName': 'Bob',
          'email': 'bob@example.com',
          'username': 'bob',
          'discoverable': false,
          'createdBy': 'system',
          'createdAt': DateTime(2024, 1, 1),
          'updatedAt': DateTime(2024, 1, 1),
          'updatedBy': 'system',
        });
        await fakeFirestore.collection('usernames').doc('bob').set({
          'uid': 'uid1',
        });

        final profile = await repo.getUserByUsername('  Bob  ');
        expect(profile, isNotNull);
        expect(profile!.uid, 'uid1');
      });
    });

    group('claimUsername', () {
      test('claims username and updates profile', () async {
        await fakeFirestore.collection('users').doc('uid1').set({
          'uid': 'uid1',
          'displayName': 'Alice',
          'email': 'alice@example.com',
          'username': null,
          'createdBy': 'system',
          'createdAt': DateTime(2024, 1, 1),
          'updatedAt': DateTime(2024, 1, 1),
          'updatedBy': 'system',
        });

        await repo.claimUsername(uid: 'uid1', username: 'alice');

        final reservation =
            await fakeFirestore.collection('usernames').doc('alice').get();
        expect(reservation.exists, isTrue);
        expect(reservation.data()!['uid'], 'uid1');

        final user =
            await fakeFirestore.collection('users').doc('uid1').get();
        expect(user.data()!['username'], 'alice');
      });

      test('throws when username already taken by another user', () async {
        await fakeFirestore.collection('users').doc('uid1').set({
          'uid': 'uid1',
          'displayName': 'Alice',
          'email': 'alice@example.com',
          'username': null,
          'createdBy': 'system',
          'createdAt': DateTime(2024, 1, 1),
          'updatedAt': DateTime(2024, 1, 1),
          'updatedBy': 'system',
        });
        await fakeFirestore.collection('usernames').doc('alice').set({
          'uid': 'uid2',
        });

        expect(
          () => repo.claimUsername(uid: 'uid1', username: 'alice'),
          throwsA(isA<UsernameAlreadyTakenException>()),
        );
      });

      test('idempotent when same user reclaims', () async {
        await fakeFirestore.collection('users').doc('uid1').set({
          'uid': 'uid1',
          'displayName': 'Alice',
          'email': 'alice@example.com',
          'username': null,
          'createdBy': 'system',
          'createdAt': DateTime(2024, 1, 1),
          'updatedAt': DateTime(2024, 1, 1),
          'updatedBy': 'system',
        });
        await fakeFirestore.collection('usernames').doc('alice').set({
          'uid': 'uid1',
        });

        // Should not throw
        await repo.claimUsername(uid: 'uid1', username: 'alice');
      });
    });

    group('isUsernameTaken', () {
      test('returns true for taken username', () async {
        await fakeFirestore.collection('usernames').doc('alice').set({
          'uid': 'uid1',
        });

        expect(await repo.isUsernameTaken('alice'), isTrue);
      });

      test('returns false for available username', () async {
        expect(await repo.isUsernameTaken('alice'), isFalse);
      });
    });

    group('watchUserProfile', () {
      test('streams profile changes', () async {
        await fakeFirestore.collection('users').doc('uid1').set({
          'uid': 'uid1',
          'displayName': 'Alice',
          'email': 'alice@example.com',
          'username': 'alice',
          'discoverable': false,
          'createdBy': 'system',
          'createdAt': DateTime(2024, 1, 1),
          'updatedAt': DateTime(2024, 1, 1),
          'updatedBy': 'system',
        });

        final profile = await repo.watchUserProfile('uid1').first;
        expect(profile, isNotNull);
        expect(profile!.displayName, 'Alice');
      });

      test('returns null for non-existent user', () async {
        final profile = await repo.watchUserProfile('nobody').first;
        expect(profile, isNull);
      });
    });
  });
}
