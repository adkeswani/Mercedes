import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_stage1/enums.dart';
import 'package:foundation_stage1/notification.dart';

void main() {
  group('AppNotification', () {
    test('constructor with defaults', () {
      final notification = AppNotification(
        id: 'n1',
        recipientId: 'athlete1',
        type: NotificationType.workoutAssigned,
        title: 'New workout assigned',
        createdAt: DateTime(2024, 2, 1),
      );
      expect(notification.id, 'n1');
      expect(notification.isRead, isFalse);
      expect(notification.isUnread, isTrue);
    });

    test('read notification', () {
      final notification = AppNotification(
        id: 'n1',
        recipientId: 'athlete1',
        type: NotificationType.comment,
        title: 'New comment',
        body: 'Coach left a comment on your workout',
        programId: 'prog1',
        read: true,
        createdAt: DateTime(2024, 2, 1),
      );
      expect(notification.isRead, isTrue);
      expect(notification.isUnread, isFalse);
    });

    test('notification with all optional fields', () {
      final notification = AppNotification(
        id: 'n1',
        recipientId: 'athlete1',
        type: NotificationType.comment,
        title: 'New comment',
        body: 'Check your workout',
        programId: 'prog1',
        workoutInstanceId: 'wi1',
        commentId: 'c1',
        createdAt: DateTime(2024, 2, 1),
      );
      expect(notification.programId, 'prog1');
      expect(notification.workoutInstanceId, 'wi1');
      expect(notification.commentId, 'c1');
    });

    test('validate throws on empty id', () {
      final notification = AppNotification(
        id: '',
        recipientId: 'athlete1',
        type: NotificationType.comment,
        title: 'Test',
        createdAt: DateTime(2024, 2, 1),
      );
      expect(() => notification.validate(), throwsArgumentError);
    });

    test('validate throws on empty recipientId', () {
      final notification = AppNotification(
        id: 'n1',
        recipientId: '',
        type: NotificationType.comment,
        title: 'Test',
        createdAt: DateTime(2024, 2, 1),
      );
      expect(() => notification.validate(), throwsArgumentError);
    });

    test('validate throws on empty title', () {
      final notification = AppNotification(
        id: 'n1',
        recipientId: 'athlete1',
        type: NotificationType.comment,
        title: '',
        createdAt: DateTime(2024, 2, 1),
      );
      expect(() => notification.validate(), throwsArgumentError);
    });

    test('validate succeeds for valid notification', () {
      final notification = AppNotification(
        id: 'n1',
        recipientId: 'athlete1',
        type: NotificationType.enrollment,
        title: 'You have been enrolled',
        createdAt: DateTime(2024, 2, 1),
      );
      expect(() => notification.validate(), returnsNormally);
    });

    test('all notification types can be created', () {
      for (final type in NotificationType.values) {
        final notification = AppNotification(
          id: 'n_${type.name}',
          recipientId: 'user1',
          type: type,
          title: 'Notification for ${type.name}',
          createdAt: DateTime(2024, 2, 1),
        );
        expect(() => notification.validate(), returnsNormally);
      }
    });
  });
}
