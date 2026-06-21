import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage4/features/auth/data/auth_repository.dart';

/// Provides the [AuthRepository] singleton.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// Streams the current Firebase [User] (null when signed out).
///
/// Widgets that depend on auth state should watch this provider.
/// It automatically updates when the user signs in or out.
final authStateProvider = StreamProvider<User?>((ref) {
  final repo = ref.watch(authRepositoryProvider);

  return repo.authStateChanges();
});
