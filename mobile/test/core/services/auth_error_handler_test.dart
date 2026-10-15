
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/auth_error_handler.dart';

void main() {
  group('AuthErrorHandler', () {
    String messageFor(String code, AuthAction action) {
      return AuthErrorHandler.getMessage(
        FirebaseAuthException(code: code),
        action: action,
      );
    }

    test('returns generic message for invalid login credentials', () {
      expect(
        messageFor('invalid-credential', AuthAction.login),
        'Invalid email or password.',
      );
    });

    test('returns a validation message for invalid email', () {
      expect(
        messageFor('invalid-email', AuthAction.login),
        'Please enter a valid email address.',
      );
    });

    test('returns a message for an existing email', () {
      expect(
        messageFor('email-already-in-use', AuthAction.register),
        'An account already exists with this email.',
      );
    });

    test('returns a message for a weak password', () {
      expect(
        messageFor('weak-password', AuthAction.register),
        'Please choose a stronger password.',
      );
    });

    test('returns a message for too many requests', () {
      expect(
        messageFor('too-many-requests', AuthAction.login),
        'Too many attempts. Please try again later.',
      );
    });

    test('returns a network error message', () {
      expect(
        messageFor('network-request-failed', AuthAction.login),
        'Network error. Check your internet connection.',
      );
    });

    test('returns a generic password reset error', () {
      expect(
        messageFor('unknown-error', AuthAction.passwordReset),
        'Unable to send reset email. Please try again.',
      );
    });

    test('does not expose raw Firebase messages for unknown errors', () {
      final exception = FirebaseAuthException(
        code: 'unknown-error',
        message: 'Internal Firebase details',
      );

      expect(
        AuthErrorHandler.getMessage(
          exception,
          action: AuthAction.login,
        ),
        'Something went wrong. Please try again.',
      );
    });
  });
}