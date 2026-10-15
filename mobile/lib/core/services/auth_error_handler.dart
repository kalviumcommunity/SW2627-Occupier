import 'package:firebase_auth/firebase_auth.dart';

class AuthErrorHandler {
  AuthErrorHandler._();

  static String getMessage(
    FirebaseAuthException exception, {
    required AuthAction action,
  }) {
    switch (exception.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return action == AuthAction.login
            ? 'Invalid email or password.'
            : 'Unable to authenticate. Please check your details.';

      case 'email-already-in-use':
        return 'An account already exists with this email.';

      case 'weak-password':
        return 'Please choose a stronger password.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'network-request-failed':
        return 'Network error. Check your internet connection.';

      case 'operation-not-allowed':
        return 'This authentication method is not enabled.';

      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';

      case 'requires-recent-login':
        return 'Please sign in again before retrying this action.';

      default:
        if (action == AuthAction.passwordReset) {
          return 'Unable to send reset email. Please try again.';
        }
        return 'Something went wrong. Please try again.';
    }
  }
}

enum AuthAction {
  login,
  register,
  passwordReset,
}
