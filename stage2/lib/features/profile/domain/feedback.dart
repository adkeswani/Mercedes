import 'package:stage2/core/enums.dart';

/// In-app feedback submitted by a user.
///
/// Feedback documents are write-only for users (they can create but
/// not read others' feedback). Admin reviews feedback via a dashboard.
class Feedback {

  Feedback({
    required this.id,
    required this.userId,
    required this.type,
    required this.body,
    required this.appVersion, required this.platform, required this.deviceModel, required this.screenName, required this.createdAt, required this.updatedAt, this.screenshotUrl,
    this.status = FeedbackStatus.newItem,
    this.adminNotes,
  });
  final String id;
  final String userId;
  final FeedbackType type;
  final String body;
  final String? screenshotUrl;
  final String appVersion;
  final String platform;
  final String deviceModel;
  final String screenName;
  final FeedbackStatus status;
  final String? adminNotes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether this feedback has been reviewed by an admin.
  bool get isReviewed => status != FeedbackStatus.newItem;

  /// Whether this feedback has been resolved.
  bool get isResolved => status == FeedbackStatus.resolved;

  /// Validates all required fields.
  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (userId.isEmpty) {
      throw ArgumentError('userId cannot be empty');
    }
    if (body.isEmpty) {
      throw ArgumentError('body cannot be empty');
    }
    if (appVersion.isEmpty) {
      throw ArgumentError('appVersion cannot be empty');
    }
    if (platform.isEmpty) {
      throw ArgumentError('platform cannot be empty');
    }
    if (deviceModel.isEmpty) {
      throw ArgumentError('deviceModel cannot be empty');
    }
    if (screenName.isEmpty) {
      throw ArgumentError('screenName cannot be empty');
    }

    // Platform must be android or ios
    if (platform != 'android' && platform != 'ios') {
      throw ArgumentError('platform must be "android" or "ios"');
    }

    if (createdAt.isAfter(updatedAt)) {
      throw ArgumentError('createdAt must be <= updatedAt');
    }
  }
}
