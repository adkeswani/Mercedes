import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Repository for Firebase Authentication operations.
///
/// Wraps [FirebaseAuth] and [GoogleSignIn] to provide a clean
/// interface for auth operations. On mobile, uses the GoogleSignIn
/// plugin; on web, uses Firebase Auth's built-in popup flow.
class AuthRepository {
  AuthRepository({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _injectedGoogleSignIn = googleSignIn;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn? _injectedGoogleSignIn;

  // Lazy-init: avoids google_sign_in_web crash on construction (requires clientId).
  GoogleSignIn? _googleSignIn;
  GoogleSignIn get _mobileGoogleSignIn =>
      _googleSignIn ??= _injectedGoogleSignIn ?? GoogleSignIn();

  /// Stream of auth state changes (sign-in, sign-out, token refresh).
  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  /// The currently signed-in user, or null.
  User? get currentUser => _firebaseAuth.currentUser;

  /// Signs in with Google.
  ///
  /// On mobile: opens the Google consent UI via the GoogleSignIn plugin,
  /// exchanges the credential with Firebase Auth.
  /// On web: uses Firebase Auth's signInWithPopup for a seamless browser flow.
  ///
  /// Returns null if the user cancels the sign-in flow.
  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      return _signInWithGoogleWeb();
    }
    return _signInWithGoogleMobile();
  }

  Future<UserCredential?> _signInWithGoogleWeb() async {
    final provider = GoogleAuthProvider();
    try {
      return await _firebaseAuth.signInWithPopup(provider);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return null;
      }
      rethrow;
    }
  }

  Future<UserCredential?> _signInWithGoogleMobile() async {
    final googleUser = await _mobileGoogleSignIn.signIn();
    if (googleUser == null) {
      return null;
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return _firebaseAuth.signInWithCredential(credential);
  }

  /// Signs out of both Firebase and Google.
  Future<void> signOut() async {
    if (kIsWeb) {
      await _firebaseAuth.signOut();
    } else {
      await Future.wait([
        _firebaseAuth.signOut(),
        _mobileGoogleSignIn.signOut(),
      ]);
    }
  }
}
