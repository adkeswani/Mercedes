import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage3/features/auth/domain/user_profile.dart';

/// Firestore repository for user profiles and username management.
///
/// Handles CRUD operations on `users/{uid}` documents and
/// username uniqueness enforcement via `usernames/{username}`.
class UserProfileRepository {
  UserProfileRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _usernamesRef =>
      _firestore.collection('usernames');

  /// Streams the user profile for [uid], or null if not found.
  ///
  /// Used to detect when the Cloud Function has created the
  /// initial user doc after first sign-in.
  Stream<UserProfile?> watchUserProfile(String uid) {
    return _usersRef.doc(uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return _fromMap(snap.data()!, snap.id);
    });
  }

  /// One-shot read of the user profile for [uid].
  Future<UserProfile?> getUserProfile(String uid) async {
    final snap = await _usersRef.doc(uid).get();
    if (!snap.exists || snap.data() == null) return null;
    return _fromMap(snap.data()!, snap.id);
  }

  /// Checks whether [username] (canonical form) is already claimed.
  Future<bool> isUsernameTaken(String username) async {
    final canonical = canonicalizeUsername(username);
    final snap = await _usernamesRef.doc(canonical).get();
    return snap.exists;
  }

  /// Looks up a user profile by exact username.
  ///
  /// Returns the profile if found, or null if the username doesn't exist.
  /// Used for athlete enrollment (exact match, privacy-safe).
  Future<UserProfile?> getUserByUsername(String username) async {
    final canonical = canonicalizeUsername(username);
    final reservation = await _usernamesRef.doc(canonical).get();
    if (!reservation.exists || reservation.data() == null) return null;

    final uid = reservation.data()!['uid'] as String?;
    if (uid == null) return null;

    return getUserProfile(uid);
  }

  /// Claims [username] for user [uid] in an atomic transaction.
  ///
  /// Creates the `usernames/{canonical}` reservation and updates
  /// `users/{uid}.username`. The transaction ensures:
  /// - If the username is already taken by another user, it fails.
  /// - If the username is already claimed by this uid (retry),
  ///   it succeeds idempotently.
  Future<void> claimUsername({
    required String uid,
    required String username,
  }) async {
    final canonical = canonicalizeUsername(username);
    _validateUsernameFormat(canonical);

    await _firestore.runTransaction((tx) async {
      final reservationRef = _usernamesRef.doc(canonical);
      final userRef = _usersRef.doc(uid);

      final reservationSnap = await tx.get(reservationRef);

      if (reservationSnap.exists) {
        final existingUid = reservationSnap.data()?['uid'] as String?;
        if (existingUid == uid) {
          // Idempotent: already claimed by this user
          return;
        }
        throw UsernameAlreadyTakenException(canonical);
      }

      tx.set(reservationRef, {'uid': uid});
      tx.update(userRef, {
        'username': canonical,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
    });
  }

  /// Converts a raw username input to its canonical storage form.
  static String canonicalizeUsername(String raw) {
    return raw.trim().toLowerCase();
  }

  /// Validates the canonical username format.
  static void _validateUsernameFormat(String canonical) {
    if (canonical.length < 3) {
      throw ArgumentError('Username must be at least 3 characters');
    }
    if (canonical.length > 30) {
      throw ArgumentError('Username must be at most 30 characters');
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(canonical)) {
      throw ArgumentError(
        'Username may only contain lowercase letters, numbers, and underscores',
      );
    }
  }

  /// Validates a username and returns null if valid, or an error message.
  ///
  /// Use this for form validation before attempting to claim.
  static String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Username is required';
    }
    final canonical = canonicalizeUsername(value);
    if (canonical.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (canonical.length > 30) {
      return 'Username must be at most 30 characters';
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(canonical)) {
      return 'Only lowercase letters, numbers, and underscores';
    }
    return null;
  }

  UserProfile _fromMap(Map<String, dynamic> data, String docId) {
    return UserProfile(
      uid: data['uid'] as String? ?? docId,
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      username: data['username'] as String?,
      photoUrl: data['photoUrl'] as String?,
      discoverable: data['discoverable'] as bool? ?? false,
      createdAt: _timestampToDateTime(data['createdAt']),
      createdBy: data['createdBy'] as String? ?? 'system',
      updatedAt: _timestampToDateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String? ?? 'system',
      deletedAt: data['deletedAt'] != null
          ? _timestampToDateTime(data['deletedAt'])
          : null,
      deletedBy: data['deletedBy'] as String?,
    );
  }

  DateTime _timestampToDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }
}

/// Thrown when a username is already claimed by another user.
class UsernameAlreadyTakenException implements Exception {
  UsernameAlreadyTakenException(this.username);

  final String username;

  @override
  String toString() => 'Username "$username" is already taken';
}
