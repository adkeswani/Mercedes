import 'package:flutter_test/flutter_test.dart';
import 'package:stage3/features/auth/domain/user_profile.dart';

void main() {
  group('UserProfile', () {
    test('constructor with defaults', () {
      final profile = UserProfile(
        uid: 'user1',
        displayName: 'John Doe',
        username: 'johndoe',
        email: 'john@example.com',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'system',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'system',
      );
      expect(profile.uid, 'user1');
      expect(profile.displayName, 'John Doe');
      expect(profile.discoverable, isFalse);
      expect(profile.photoUrl, isNull);
      expect(profile.isDeleted, isFalse);
    });

    test('discoverable profile with photo', () {
      final profile = UserProfile(
        uid: 'user1',
        displayName: 'John Doe',
        username: 'johndoe',
        email: 'john@example.com',
        photoUrl: 'https://example.com/photo.jpg',
        discoverable: true,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'system',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'user1',
      );
      expect(profile.discoverable, isTrue);
      expect(profile.photoUrl, isNotNull);
    });

    test('soft-deleted profile', () {
      final profile = UserProfile(
        uid: 'user1',
        displayName: 'John Doe',
        username: 'johndoe',
        email: 'john@example.com',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'system',
        updatedAt: DateTime(2024, 3, 1),
        updatedBy: 'system',
        deletedAt: DateTime(2024, 3, 1),
        deletedBy: 'system',
      );
      expect(profile.isDeleted, isTrue);
    });

    test('validate throws on empty uid', () {
      final profile = _makeProfile(uid: '');
      expect(() => profile.validate(), throwsArgumentError);
    });

    test('validate throws on empty displayName', () {
      final profile = _makeProfile(displayName: '');
      expect(() => profile.validate(), throwsArgumentError);
    });

    test('validate throws on empty username when set', () {
      final profile = _makeProfile(username: '');
      expect(() => profile.validate(), throwsArgumentError);
    });

    test('validate succeeds with null username (pre-onboarding)', () {
      final profile = _makeProfile(username: null);
      expect(() => profile.validate(), returnsNormally);
      expect(profile.hasUsername, isFalse);
    });

    test('hasUsername is true when username is set', () {
      final profile = _makeProfile(username: 'johndoe');
      expect(profile.hasUsername, isTrue);
    });

    test('validate throws on empty email', () {
      final profile = _makeProfile(email: '');
      expect(() => profile.validate(), throwsArgumentError);
    });

    test('validate throws on empty createdBy', () {
      final profile = _makeProfile(createdBy: '');
      expect(() => profile.validate(), throwsArgumentError);
    });

    test('validate throws on bad timestamp order', () {
      final profile = UserProfile(
        uid: 'user1',
        displayName: 'John Doe',
        username: 'johndoe',
        email: 'john@example.com',
        createdAt: DateTime(2024, 3, 1),
        createdBy: 'system',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'system',
      );
      expect(() => profile.validate(), throwsArgumentError);
    });

    test('validate succeeds for valid profile', () {
      final profile = _makeProfile();
      expect(() => profile.validate(), returnsNormally);
    });
  });

  group('UsernameReservation', () {
    test('constructor', () {
      final reservation = UsernameReservation(
        username: 'johndoe',
        uid: 'user1',
      );
      expect(reservation.username, 'johndoe');
      expect(reservation.uid, 'user1');
    });

    test('validate throws on empty username', () {
      final reservation = UsernameReservation(
        username: '',
        uid: 'user1',
      );
      expect(() => reservation.validate(), throwsArgumentError);
    });

    test('validate throws on empty uid', () {
      final reservation = UsernameReservation(
        username: 'johndoe',
        uid: '',
      );
      expect(() => reservation.validate(), throwsArgumentError);
    });
  });
}

/// Helper to create a minimal valid UserProfile with overrides.
UserProfile _makeProfile({
  String uid = 'user1',
  String displayName = 'John Doe',
  String? username = 'johndoe',
  String email = 'john@example.com',
  String createdBy = 'system',
}) {
  return UserProfile(
    uid: uid,
    displayName: displayName,
    username: username,
    email: email,
    createdAt: DateTime(2024, 1, 1),
    createdBy: createdBy,
    updatedAt: DateTime(2024, 1, 1),
    updatedBy: 'system',
  );
}
