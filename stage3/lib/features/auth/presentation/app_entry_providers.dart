import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage3/features/auth/data/user_profile_repository.dart';
import 'package:stage3/features/auth/domain/user_profile.dart';
import 'package:stage3/features/auth/presentation/auth_providers.dart';

/// The possible states of the app entry flow.
enum AppEntryState {
  /// User is not signed in.
  signedOut,

  /// Signed in, waiting for the Cloud Function to create the
  /// Firestore user doc (or for the first snapshot to arrive).
  waitingForProfile,

  /// Profile exists but username is not set — show onboarding.
  needsOnboarding,

  /// Profile complete — show the main app.
  ready,

  /// Something went wrong (e.g. profile never appeared).
  error,
}

/// Provides the [UserProfileRepository] singleton.
final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository();
});

/// Streams the current user's [UserProfile], or null if not found.
///
/// Automatically switches to the correct uid when auth state changes.
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.valueOrNull;

  if (user == null) return Stream.value(null);

  final repo = ref.watch(userProfileRepositoryProvider);
  return repo.watchUserProfile(user.uid);
});

/// Single source of truth for the app entry flow.
///
/// The router watches only this provider to decide which screen
/// to show. States flow: signedOut → waitingForProfile →
/// needsOnboarding | ready.
final appEntryStateProvider = Provider<AppEntryState>((ref) {
  final authState = ref.watch(authStateProvider);
  final profileState = ref.watch(userProfileProvider);

  return authState.when(
    loading: () => AppEntryState.signedOut,
    error: (_, __) => AppEntryState.error,
    data: (User? user) {
      if (user == null) return AppEntryState.signedOut;

      return profileState.when(
        loading: () => AppEntryState.waitingForProfile,
        error: (_, __) => AppEntryState.error,
        data: (UserProfile? profile) {
          if (profile == null) return AppEntryState.waitingForProfile;
          if (!profile.hasUsername) return AppEntryState.needsOnboarding;
          return AppEntryState.ready;
        },
      );
    },
  );
});
