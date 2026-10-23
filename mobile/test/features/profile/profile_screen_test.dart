import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/profile/screens/profile_screen.dart';
import 'package:mobile/models/user.dart';

void main() {
  testWidgets('shows loading and a retry action when profile loading fails', (
    tester,
  ) async {
    final attempts = <Completer<OccupierUser?>>[];

    Future<OccupierUser?> loadProfile() {
      final attempt = Completer<OccupierUser?>();
      attempts.add(attempt);
      return attempt.future;
    }

    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(profileLoader: loadProfile)),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    attempts.first.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to load your profile. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(attempts, hasLength(2));
    attempts.last.complete(
      const OccupierUser(
        uid: 'member-1',
        name: 'Test Member',
        email: 'member@example.com',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Member'), findsOneWidget);
  });

  testWidgets('shows a recoverable state when the profile is missing', (
    tester,
  ) async {
    final attempts = <Completer<OccupierUser?>>[];

    Future<OccupierUser?> loadProfile() {
      final attempt = Completer<OccupierUser?>();
      attempts.add(attempt);
      return attempt.future;
    }

    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(profileLoader: loadProfile)),
    );

    attempts.first.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('Your profile is unavailable.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(attempts, hasLength(2));
    attempts.last.complete(
      const OccupierUser(
        uid: 'member-1',
        name: 'Test Member',
        email: 'member@example.com',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Member'), findsOneWidget);
  });
}
