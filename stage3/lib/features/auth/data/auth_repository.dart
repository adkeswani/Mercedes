import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Repository for Firebase Authentication operations.
///
/// Wraps [FirebaseAuth] and [GoogleSignIn] to provide a clean
/// interface for auth operations. The app listens to
/// [authStateChanges] to react to sign-in/sign-out events.
class AuthRepository {
  AuthRepository({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  /// Stream of auth state changes (sign-in, sign-out, token refresh).
  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  /// The currently signed-in user, or null.
  User? get currentUser => _firebaseAuth.currentUser;

  /// Signs in with Google.
  ///
  /// Opens the Google consent UI, exchanges the credential with
  /// Firebase Auth, and returns the [UserCredential]. On first
  /// sign-in, the `onUserCreated` Cloud Function fires to create
  /// the Firestore user document.
  ///
  /// Returns null if the user cancels the sign-in flow.
  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
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
    await Future.wait([
      _firebaseAuth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }
}
