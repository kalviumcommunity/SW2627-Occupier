import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/constants/app_routes.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('waits for auth and redirects unauthenticated routes', (
    tester,
  ) async {
    final authChanges = StreamController<String?>.broadcast();

    await tester.pumpWidget(
      OccupierApp(
        authStateChanges: authChanges.stream,
        routeBuilders: _testRoutes,
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    authChanges.add(null);
    await tester.pumpAndSettle();

    for (final route in _protectedRouteNames) {
      await tester.tap(find.byKey(ValueKey<String>(route)));
      await tester.pumpAndSettle();

      expect(find.text('Test Login'), findsOneWidget);
      expect(find.text('Protected Profile'), findsNothing);
      expect(find.text('Protected Dashboard'), findsNothing);
    }

    await authChanges.close();
  });

  testWidgets(
    'authenticated users access protected routes and logout redirects',
    (tester) async {
      final authChanges = StreamController<String?>.broadcast();

      await tester.pumpWidget(
        OccupierApp(
          authStateChanges: authChanges.stream,
          routeBuilders: _testRoutes,
        ),
      );

      authChanges.add('member-1');
      await tester.pumpAndSettle();

      expect(find.text('Protected Dashboard'), findsOneWidget);
      await tester.tap(find.text('Open profile'));
      await tester.pumpAndSettle();
      expect(find.text('Protected Profile'), findsOneWidget);

      authChanges.add(null);
      await tester.pumpAndSettle();

      expect(find.text('Test Login'), findsOneWidget);
      expect(find.text('Protected Profile'), findsNothing);

      await authChanges.close();
    },
  );

  testWidgets('authenticated users are redirected from public auth routes', (
    tester,
  ) async {
    final authChanges = StreamController<String?>.broadcast();

    await tester.pumpWidget(
      OccupierApp(
        authStateChanges: authChanges.stream,
        routeBuilders: _testRoutes,
      ),
    );

    authChanges.add('member-1');
    await tester.pumpAndSettle();

    for (final label in [
      'Open login',
      'Open registration',
      'Open password reset',
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(find.text('Protected Dashboard'), findsOneWidget);
      expect(find.text('Test Login'), findsNothing);
      expect(find.text('Test Register'), findsNothing);
      expect(find.text('Test Password Reset'), findsNothing);
    }

    await authChanges.close();
  });

  testWidgets('signed-out users can access registration and password reset', (
    tester,
  ) async {
    final authChanges = StreamController<String?>.broadcast();

    await tester.pumpWidget(
      OccupierApp(
        authStateChanges: authChanges.stream,
        routeBuilders: _testRoutes,
      ),
    );

    authChanges.add(null);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open registration'));
    await tester.pumpAndSettle();
    expect(find.text('Test Register'), findsOneWidget);

    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();
    expect(find.text('Test Login'), findsOneWidget);

    await tester.tap(find.text('Open password reset'));
    await tester.pumpAndSettle();
    expect(find.text('Test Password Reset'), findsOneWidget);

    await authChanges.close();
  });

  testWidgets('shows an error when the initial auth check fails', (
    tester,
  ) async {
    final authChanges = StreamController<String?>.broadcast();

    await tester.pumpWidget(
      OccupierApp(
        authStateChanges: authChanges.stream,
        routeBuilders: _testRoutes,
      ),
    );

    authChanges.addError(StateError('Auth stream failed'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to check your sign-in status.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await authChanges.close();
  });
}

final Map<String, WidgetBuilder> _testRoutes = {
  AppRoutes.login: (_) => Scaffold(
    body: Column(
      children: [
        const Text('Test Login'),
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.register),
            child: const Text('Open registration'),
          ),
        ),
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.forgotPassword),
            child: const Text('Open password reset'),
          ),
        ),
        for (final route in _protectedRouteNames)
          Builder(
            builder: (context) => TextButton(
              key: ValueKey<String>(route),
              onPressed: () => Navigator.of(context).pushNamed(route),
              child: Text(route),
            ),
          ),
      ],
    ),
  ),
  AppRoutes.dashboard: (_) => Scaffold(
    body: Column(
      children: [
        const Text('Protected Dashboard'),
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.profile),
            child: const Text('Open profile'),
          ),
        ),
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.login),
            child: const Text('Open login'),
          ),
        ),
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.register),
            child: const Text('Open registration'),
          ),
        ),
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.forgotPassword),
            child: const Text('Open password reset'),
          ),
        ),
      ],
    ),
  ),
  AppRoutes.profile: (_) => const Scaffold(body: Text('Protected Profile')),
  AppRoutes.register: (_) => Scaffold(
    body: Column(
      children: [
        const Text('Test Register'),
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Login'),
          ),
        ),
      ],
    ),
  ),
  AppRoutes.forgotPassword: (_) =>
      const Scaffold(body: Text('Test Password Reset')),
};

const _protectedRouteNames = [
  AppRoutes.dashboard,
  AppRoutes.branches,
  AppRoutes.desks,
  AppRoutes.meetingRooms,
  AppRoutes.bookings,
  AppRoutes.occupancy,
  AppRoutes.profile,
  AppRoutes.walkInCheckIn,
];
