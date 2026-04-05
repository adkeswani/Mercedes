import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_stage1/enums.dart';
import 'package:foundation_stage1/feedback.dart';

void main() {
  group('Feedback', () {
    test('constructor with defaults', () {
      final feedback = Feedback(
        id: 'fb1',
        userId: 'user1',
        type: FeedbackType.bug,
        body: 'The timer resets when I switch apps',
        appVersion: '1.0.0',
        platform: 'android',
        deviceModel: 'Pixel 7',
        screenName: 'WorkoutScreen',
        createdAt: DateTime(2024, 2, 1),
        updatedAt: DateTime(2024, 2, 1),
      );
      expect(feedback.id, 'fb1');
      expect(feedback.status, FeedbackStatus.newItem);
      expect(feedback.isReviewed, isFalse);
      expect(feedback.isResolved, isFalse);
    });

    test('reviewed feedback', () {
      final feedback = Feedback(
        id: 'fb1',
        userId: 'user1',
        type: FeedbackType.feature,
        body: 'Add dark mode',
        appVersion: '1.0.0',
        platform: 'ios',
        deviceModel: 'iPhone 15',
        screenName: 'SettingsScreen',
        status: FeedbackStatus.reviewed,
        adminNotes: 'Planned for v2',
        createdAt: DateTime(2024, 2, 1),
        updatedAt: DateTime(2024, 2, 5),
      );
      expect(feedback.isReviewed, isTrue);
      expect(feedback.isResolved, isFalse);
      expect(feedback.adminNotes, 'Planned for v2');
    });

    test('resolved feedback', () {
      final feedback = Feedback(
        id: 'fb1',
        userId: 'user1',
        type: FeedbackType.bug,
        body: 'Fixed crash',
        appVersion: '1.0.0',
        platform: 'android',
        deviceModel: 'Pixel 7',
        screenName: 'HomeScreen',
        status: FeedbackStatus.resolved,
        createdAt: DateTime(2024, 2, 1),
        updatedAt: DateTime(2024, 3, 1),
      );
      expect(feedback.isResolved, isTrue);
      expect(feedback.isReviewed, isTrue);
    });

    test('feedback with screenshot', () {
      final feedback = Feedback(
        id: 'fb1',
        userId: 'user1',
        type: FeedbackType.bug,
        body: 'See attached',
        screenshotUrl: 'https://example.com/screenshot.png',
        appVersion: '1.0.0',
        platform: 'android',
        deviceModel: 'Pixel 7',
        screenName: 'WorkoutScreen',
        createdAt: DateTime(2024, 2, 1),
        updatedAt: DateTime(2024, 2, 1),
      );
      expect(feedback.screenshotUrl, isNotNull);
    });

    test('validate throws on empty id', () {
      final feedback = _makeFeedback(id: '');
      expect(() => feedback.validate(), throwsArgumentError);
    });

    test('validate throws on empty userId', () {
      final feedback = _makeFeedback(userId: '');
      expect(() => feedback.validate(), throwsArgumentError);
    });

    test('validate throws on empty body', () {
      final feedback = _makeFeedback(body: '');
      expect(() => feedback.validate(), throwsArgumentError);
    });

    test('validate throws on empty appVersion', () {
      final feedback = _makeFeedback(appVersion: '');
      expect(() => feedback.validate(), throwsArgumentError);
    });

    test('validate throws on invalid platform', () {
      final feedback = _makeFeedback(platform: 'web');
      expect(() => feedback.validate(), throwsArgumentError);
    });

    test('validate throws on empty deviceModel', () {
      final feedback = _makeFeedback(deviceModel: '');
      expect(() => feedback.validate(), throwsArgumentError);
    });

    test('validate throws on empty screenName', () {
      final feedback = _makeFeedback(screenName: '');
      expect(() => feedback.validate(), throwsArgumentError);
    });

    test('validate throws on bad timestamp order', () {
      final feedback = Feedback(
        id: 'fb1',
        userId: 'user1',
        type: FeedbackType.bug,
        body: 'Test',
        appVersion: '1.0.0',
        platform: 'android',
        deviceModel: 'Pixel 7',
        screenName: 'HomeScreen',
        createdAt: DateTime(2024, 3, 1),
        updatedAt: DateTime(2024, 1, 1),
      );
      expect(() => feedback.validate(), throwsArgumentError);
    });

    test('validate succeeds for valid android feedback', () {
      final feedback = _makeFeedback(platform: 'android');
      expect(() => feedback.validate(), returnsNormally);
    });

    test('validate succeeds for valid ios feedback', () {
      final feedback = _makeFeedback(platform: 'ios');
      expect(() => feedback.validate(), returnsNormally);
    });

    test('all feedback types can be created', () {
      for (final type in FeedbackType.values) {
        final feedback = Feedback(
          id: 'fb_${type.name}',
          userId: 'user1',
          type: type,
          body: 'Feedback for ${type.name}',
          appVersion: '1.0.0',
          platform: 'android',
          deviceModel: 'Pixel 7',
          screenName: 'HomeScreen',
          createdAt: DateTime(2024, 2, 1),
          updatedAt: DateTime(2024, 2, 1),
        );
        expect(() => feedback.validate(), returnsNormally);
      }
    });
  });
}

/// Helper to create a minimal valid Feedback with overrides.
Feedback _makeFeedback({
  String id = 'fb1',
  String userId = 'user1',
  String body = 'Timer resets when switching apps',
  String appVersion = '1.0.0',
  String platform = 'android',
  String deviceModel = 'Pixel 7',
  String screenName = 'WorkoutScreen',
}) {
  return Feedback(
    id: id,
    userId: userId,
    type: FeedbackType.bug,
    body: body,
    appVersion: appVersion,
    platform: platform,
    deviceModel: deviceModel,
    screenName: screenName,
    createdAt: DateTime(2024, 2, 1),
    updatedAt: DateTime(2024, 2, 1),
  );
}
