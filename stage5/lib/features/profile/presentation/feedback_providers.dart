import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/profile/data/feedback_repository.dart';

const feedbackAppVersion = '0.1.0';

final feedbackRepositoryProvider = Provider<FeedbackRepository?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return null;
  }
  return FeedbackRepository(userId: user.uid);
});

String currentFeedbackPlatform() {
  if (kIsWeb) {
    return 'web';
  }
  return defaultTargetPlatform.name;
}

String currentFeedbackDeviceModel() {
  if (kIsWeb) {
    return 'web-browser';
  }
  return '${defaultTargetPlatform.name}-device';
}
