import 'package:foundation_stage1/enums.dart';

/// In-app notification delivered to a user.
///
/// Notifications are written by Cloud Functions alongside the action
/// that triggers them (e.g., template published, enrollment changed).
class AppNotification {

  AppNotification({
    required this.id,
    required this.recipientId,
    required this.type,
    required this.title,
    required this.createdAt, this.body,
    this.programId,
    this.workoutInstanceId,
    this.commentId,
    this.read = false,
  });
  final String id;
  final String recipientId;
  final NotificationType type;
  final String title;
  final String? body;
  final String? programId;
  final String? workoutInstanceId;
  final String? commentId;
  final bool read;
  final DateTime createdAt;

  /// Whether this notification has been read.
  bool get isRead => read;

  /// Whether this notification has not been read.
  bool get isUnread => !read;

  /// Validates all required fields.
  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (recipientId.isEmpty) {
      throw ArgumentError('recipientId cannot be empty');
    }
    if (title.isEmpty) {
      throw ArgumentError('title cannot be empty');
    }
  }
}
