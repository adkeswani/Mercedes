import 'package:stage2/features/auth/domain/foundation_models.dart';

/// User profile matching the Firestore users/{userId} document.
///
/// Roles are not stored on the user document — a user's role is
/// contextual per program, determined by program ownership or
/// enrollment membership.
class UserProfile with Auditable {

  UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.username,
    this.photoUrl,
    this.discoverable = false,
    this.deletedAt,
    this.deletedBy,
  });
  final String uid;
  final String displayName;

  /// Null until the user completes onboarding and claims a username.
  final String? username;
  final String email;
  final String? photoUrl;
  final bool discoverable;
  @override
  final DateTime createdAt;
  @override
  final String createdBy;
  @override
  final DateTime updatedAt;
  @override
  final String updatedBy;
  @override
  final DateTime? deletedAt;
  @override
  final String? deletedBy;

  /// Whether this user has completed onboarding (claimed a username).
  bool get hasUsername => username != null && username!.isNotEmpty;

  /// Whether this profile has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Validates all required fields, constraints, and audit ordering.
  void validate() {
    if (uid.isEmpty) {
      throw ArgumentError('uid cannot be empty');
    }
    if (displayName.isEmpty) {
      throw ArgumentError('displayName cannot be empty');
    }
    if (username != null && username!.isEmpty) {
      throw ArgumentError('username cannot be empty when set');
    }
    if (email.isEmpty) {
      throw ArgumentError('email cannot be empty');
    }
    if (createdBy.isEmpty) {
      throw ArgumentError('createdBy cannot be empty');
    }
    if (updatedBy.isEmpty) {
      throw ArgumentError('updatedBy cannot be empty');
    }

    Auditable.validateTimestamps(
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

/// Username reservation helper for uniqueness enforcement.
///
/// The `usernames/{username}` collection ensures no two users
/// can claim the same username.
class UsernameReservation {

  UsernameReservation({
    required this.username,
    required this.uid,
  });
  final String username;
  final String uid;

  /// Validates reservation fields.
  void validate() {
    if (username.isEmpty) {
      throw ArgumentError('username cannot be empty');
    }
    if (uid.isEmpty) {
      throw ArgumentError('uid cannot be empty');
    }
  }
}
