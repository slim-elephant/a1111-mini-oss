import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../firebase/firebase_status.dart';

/// Thrown for sign-in problems the UI should show as-is.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);

  @override
  String toString() => message;
}

/// Every install starts with an anonymous Firebase user. Signing in links a
/// real credential onto that user so its UID (votes, entitlements) survives.
/// If the credential already belongs to another account, we switch to it.
class AuthService {
  final FirebaseAuth? _authOverride;
  final GoogleSignIn _google;

  AuthService({FirebaseAuth? auth, GoogleSignIn? google})
      : _authOverride = auth,
        _google = google ?? GoogleSignIn();

  // Resolved lazily: FirebaseAuth.instance throws when Firebase isn't set up.
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  User? get currentUser => firebaseReady ? _auth.currentUser : null;

  /// Signs in anonymously if nobody is signed in. Never throws: the app
  /// works offline, and we retry on the next launch.
  Future<void> ensureSignedIn() async {
    if (!firebaseReady || _auth.currentUser != null) return;
    try {
      await _auth.signInAnonymously();
    } catch (e) {
      debugPrint('Anonymous sign-in failed: $e');
    }
  }

  Future<void> signInWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    await _run(
      link: (user) => user.linkWithProvider(provider),
      signIn: () => _auth.signInWithProvider(provider),
    );
  }

  Future<void> signInWithGoogle() async {
    final GoogleSignInAccount? account;
    try {
      account = await _google.signIn();
    } catch (e) {
      throw AuthFailure('Google sign-in is unavailable: $e');
    }
    if (account == null) return; // cancelled
    final tokens = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
    );
    await _withCredential(credential);
  }

  Future<void> signInWithEmail(String email, String password) async {
    await _guard(() async {
      final previous = _auth.currentUser;
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _deleteIfAnonymous(previous);
    });
  }

  Future<void> createEmailAccount(String email, String password) async {
    final credential = EmailAuthProvider.credential(
      email: email.trim(),
      password: password,
    );
    await _withCredential(credential);
  }

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  /// Signs out and starts a fresh anonymous session.
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
    await _auth.signOut();
    await ensureSignedIn();
  }

  /// Permanently deletes the signed-in account (App Store requirement).
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _guard(user.delete);
    try {
      await _google.signOut();
    } catch (_) {}
    await ensureSignedIn();
  }

  Future<void> _withCredential(AuthCredential credential) => _run(
        link: (user) => user.linkWithCredential(credential),
        signIn: () => _auth.signInWithCredential(credential),
      );

  Future<void> _run({
    required Future<UserCredential> Function(User user) link,
    required Future<UserCredential> Function() signIn,
  }) async {
    await _guard(() async {
      final user = _auth.currentUser;
      if (user == null || !user.isAnonymous) {
        await signIn();
        return;
      }
      try {
        await link(user);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use' &&
            e.code != 'email-already-in-use' &&
            e.code != 'provider-already-linked') {
          rethrow;
        }
        // Existing account: switch to it and drop the throwaway anon user.
        final cred = e.credential;
        if (cred != null) {
          await _auth.signInWithCredential(cred);
        } else if (e.code == 'email-already-in-use') {
          throw const AuthFailure(
              'An account with this email already exists. Sign in instead.');
        } else {
          await signIn();
        }
        await _deleteIfAnonymous(user);
      }
    });
  }

  Future<void> _deleteIfAnonymous(User? user) async {
    if (user == null || !user.isAnonymous) return;
    if (user.uid == _auth.currentUser?.uid) return;
    try {
      await user.delete();
    } catch (_) {
      // Orphaned anonymous users are harmless; Firebase can clean them up.
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  static String _message(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address doesn’t look right.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'weak-password':
        return 'Use at least 6 characters for the password.';
      case 'email-already-in-use':
        return 'An account with this email already exists. Sign in instead.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a few minutes.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'requires-recent-login':
        return 'For security, sign out and sign in again, then retry.';
      case 'operation-not-allowed':
        return 'This sign-in method isn’t enabled yet.';
      case 'canceled':
      case 'web-context-canceled':
        return 'Sign-in was cancelled.';
      default:
        return e.message ?? 'Sign-in failed (${e.code}).';
    }
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Emits on sign-in, sign-out and profile changes (name, photo, linking).
final authUserProvider = StreamProvider<User?>(
  (ref) => firebaseReady
      ? FirebaseAuth.instance.userChanges()
      : Stream<User?>.value(null),
);
