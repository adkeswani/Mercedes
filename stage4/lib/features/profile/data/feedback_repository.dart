import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/profile/domain/feedback.dart' as domain;

/// Submits authenticated user feedback to the write-only `feedback` collection.
class FeedbackRepository {
  FeedbackRepository({
    required this.userId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final String userId;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('feedback');

  Future<String> submit({
    required String actorId,
    required FeedbackType type,
    required String body,
    required String appVersion,
    required String platform,
    required String deviceModel,
    required String screenName,
  }) async {
    _verifyOwnership(actorId);

    final document = _collection.doc();
    final now = DateTime.now().toUtc();
    final feedback = domain.Feedback(
      id: document.id,
      userId: userId,
      type: type,
      body: body.trim(),
      appVersion: appVersion,
      platform: platform,
      deviceModel: deviceModel,
      screenName: screenName,
      createdAt: now,
      updatedAt: now,
    );
    feedback.validate();

    await document.set({
      'userId': feedback.userId,
      'type': feedback.type.name,
      'body': feedback.body,
      'appVersion': feedback.appVersion,
      'platform': feedback.platform,
      'deviceModel': feedback.deviceModel,
      'screenName': feedback.screenName,
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return document.id;
  }

  void _verifyOwnership(String actorId) {
    if (actorId != userId) {
      throw StateError('Feedback can only be submitted for the current user');
    }
  }
}
