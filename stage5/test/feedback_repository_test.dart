import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/profile/data/feedback_repository.dart';
import 'package:stage5/features/profile/domain/feedback.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FeedbackRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FeedbackRepository(
      userId: 'user1',
      firestore: firestore,
    );
  });

  test('submit creates feedback with review metadata', () async {
    final id = await repository.submit(
      actorId: 'user1',
      type: FeedbackType.feature,
      body: '  Add a weekly summary  ',
      appVersion: '0.1.0',
      platform: 'web',
      deviceModel: 'web-browser',
      screenName: 'HomeScreen',
    );

    final document = await firestore.collection('feedback').doc(id).get();
    expect(document.exists, isTrue);
    expect(document.data()!['userId'], 'user1');
    expect(document.data()!['type'], 'feature');
    expect(document.data()!['body'], 'Add a weekly summary');
    expect(document.data()!['appVersion'], '0.1.0');
    expect(document.data()!['platform'], 'web');
    expect(document.data()!['deviceModel'], 'web-browser');
    expect(document.data()!['screenName'], 'HomeScreen');
    expect(document.data()!['status'], 'new');
    expect(document.data()!['createdAt'], isNotNull);
    expect(document.data()!['updatedAt'], isNotNull);
  });

  test('submit rejects ownership mismatch before writing', () async {
    await expectLater(
      repository.submit(
        actorId: 'other-user',
        type: FeedbackType.bug,
        body: 'Something broke',
        appVersion: '0.1.0',
        platform: 'web',
        deviceModel: 'web-browser',
        screenName: 'HomeScreen',
      ),
      throwsStateError,
    );

    final snapshot = await firestore.collection('feedback').get();
    expect(snapshot.docs, isEmpty);
  });

  test('submit rejects blank and oversized bodies', () async {
    Future<String> submit(String body) => repository.submit(
          actorId: 'user1',
          type: FeedbackType.general,
          body: body,
          appVersion: '0.1.0',
          platform: 'web',
          deviceModel: 'web-browser',
          screenName: 'HomeScreen',
        );

    await expectLater(submit('   '), throwsArgumentError);
    await expectLater(
      submit('x' * (Feedback.maxBodyLength + 1)),
      throwsArgumentError,
    );
  });
}
