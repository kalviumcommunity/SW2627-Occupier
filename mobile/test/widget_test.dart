import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/constants/app_routes.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/user.dart';

void main() {
  testWidgets('waits for auth and redirects unauthenticated routes', (
    tester,
  ) async {
    final authChanges = StreamController<String?>.broadcast();

    await tester.pumpWidget(
      OccupierApp(
        authStateChanges: authChanges.stream,
        profileChanges: _memberProfile,
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
          profileChanges: _memberProfile,
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
        profileChanges: _memberProfile,
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

  testWidgets('direct unauthenticated route attempts return to login', (
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

    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pushNamed<void>(AppRoutes.occupancy);
    await tester.pumpAndSettle();

    expect(find.text('Test Login'), findsOneWidget);
    expect(find.text('Test route ${AppRoutes.occupancy}'), findsNothing);
    await authChanges.close();
  });

  testWidgets('direct protected routes follow each trusted role', (
    tester,
  ) async {
    for (final role in UserRole.values) {
      final authChanges = StreamController<String?>.broadcast();
      final profileChanges = StreamController<OccupierUser?>.broadcast();
      await tester.pumpWidget(
        OccupierApp(
          authStateChanges: authChanges.stream,
          profileChanges: (_) => profileChanges.stream,
          routeBuilders: _testRoutes,
        ),
      );

      final uid = 'user-${role.name}';
      authChanges.add(uid);
      await tester.pump();
      profileChanges.add(_profile(uid, role));
      await tester.pumpAndSettle();

      for (final route in _protectedRouteNames) {
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .pushNamed<void>(route);
        await tester.pumpAndSettle();

        final allowed = switch (route) {
          AppRoutes.desks || AppRoutes.meetingRooms =>
            role == UserRole.admin || role == UserRole.branchManager,
          AppRoutes.occupancy => role != UserRole.member,
          AppRoutes.walkInCheckIn =>
            role == UserRole.admin ||
                role == UserRole.branchManager ||
                role == UserRole.staff,
          _ => true,
        };
        if (allowed) {
          expect(
            find.text(
              route == AppRoutes.dashboard
                  ? 'Protected Dashboard'
                  : route == AppRoutes.profile
                  ? 'Protected Profile'
                  : 'Test route $route',
            ),
            findsOneWidget,
          );
        } else {
          expect(find.text('Access Denied'), findsOneWidget);
        }

        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }

      await authChanges.close();
      await profileChanges.close();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('role revocation blocks an already-open restricted route', (
    tester,
  ) async {
    final authChanges = StreamController<String?>.broadcast();
    final profileChanges = StreamController<OccupierUser?>.broadcast();
    await tester.pumpWidget(
      OccupierApp(
        authStateChanges: authChanges.stream,
        profileChanges: (_) => profileChanges.stream,
        routeBuilders: _testRoutes,
      ),
    );
    authChanges.add('admin-1');
    await tester.pump();
    profileChanges.add(_profile('admin-1', UserRole.admin));
    await tester.pumpAndSettle();

    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pushNamed<void>(AppRoutes.occupancy);
    await tester.pumpAndSettle();
    expect(find.text('Test route ${AppRoutes.occupancy}'), findsOneWidget);

    profileChanges.add(_profile('admin-1', UserRole.member));
    await tester.pump();
    await tester.pump();
    expect(find.text('Test route ${AppRoutes.occupancy}'), findsNothing);
    expect(find.text('Access Denied'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Access Denied'), findsOneWidget);

    authChanges.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Test Login'), findsOneWidget);
    expect(find.text('Access Denied'), findsNothing);

    await authChanges.close();
    await profileChanges.close();
  });

  testWidgets('account switch clears the previous role while loading', (
    tester,
  ) async {
    final authChanges = StreamController<String?>.broadcast();
    final adminProfile = StreamController<OccupierUser?>.broadcast();
    final memberProfile = StreamController<OccupierUser?>.broadcast();
    await tester.pumpWidget(
      OccupierApp(
        authStateChanges: authChanges.stream,
        profileChanges: (uid) =>
            uid == 'admin-1' ? adminProfile.stream : memberProfile.stream,
        routeBuilders: _testRoutes,
      ),
    );

    authChanges.add('admin-1');
    await tester.pump();
    adminProfile.add(_profile('admin-1', UserRole.admin));
    await tester.pumpAndSettle();
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pushNamed<void>(AppRoutes.occupancy);
    await tester.pumpAndSettle();
    expect(find.text('Test route ${AppRoutes.occupancy}'), findsOneWidget);

    authChanges.add('member-2');
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Test route ${AppRoutes.occupancy}'), findsNothing);
    expect(find.text('Access Denied'), findsNothing);

    memberProfile.add(_profile('member-2', UserRole.member));
    await tester.pumpAndSettle();
    expect(find.text('Access Denied'), findsOneWidget);

    await authChanges.close();
    await adminProfile.close();
    await memberProfile.close();
  });

  testWidgets('account switch never renders a cached prior route', (
    tester,
  ) async {
    final authChanges = StreamController<String?>.broadcast();
    final adminProfile = StreamController<OccupierUser?>.broadcast();
    await tester.pumpWidget(
      OccupierApp(
        authStateChanges: authChanges.stream,
        profileChanges: (uid) => uid == 'admin-1'
            ? adminProfile.stream
            : Stream.value(_profile(uid, UserRole.member)),
        routeBuilders: _testRoutes,
      ),
    );

    authChanges.add('admin-1');
    await tester.pump();
    adminProfile.add(_profile('admin-1', UserRole.admin));
    await tester.pumpAndSettle();
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pushNamed<void>(AppRoutes.occupancy);
    await tester.pumpAndSettle();
    expect(find.text('Test route ${AppRoutes.occupancy}'), findsOneWidget);

    authChanges.add('member-2');
    await tester.pump();
    await tester.pump();
    expect(find.text('Test route ${AppRoutes.occupancy}'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Access Denied'), findsOneWidget);
    await authChanges.close();
    await adminProfile.close();
  });

  testWidgets('profile fetch failure retries without granting access', (
    tester,
  ) async {
    final authChanges = StreamController<String?>.broadcast();
    final profileChanges = StreamController<OccupierUser?>.broadcast();
    await tester.pumpWidget(
      OccupierApp(
        authStateChanges: authChanges.stream,
        profileChanges: (_) => profileChanges.stream,
        routeBuilders: _testRoutes,
      ),
    );
    authChanges.add('member-1');
    await tester.pump();
    profileChanges.addError(StateError('Unavailable'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load your access profile.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Protected Dashboard'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    profileChanges.add(_profile('member-1', UserRole.member));
    await tester.pumpAndSettle();
    expect(find.text('Protected Dashboard'), findsOneWidget);

    await authChanges.close();
    await profileChanges.close();
  });

  testWidgets('missing or mismatched profiles deny protected routes', (
    tester,
  ) async {
    final authChanges = StreamController<String?>.broadcast();
    final profileChanges = StreamController<OccupierUser?>.broadcast();
    await tester.pumpWidget(
      OccupierApp(
        authStateChanges: authChanges.stream,
        profileChanges: (_) => profileChanges.stream,
        routeBuilders: _testRoutes,
      ),
    );
    authChanges.add('member-1');
    await tester.pump();
    profileChanges.add(_profile('another-user', UserRole.admin));
    await tester.pumpAndSettle();

    expect(find.text('Access Denied'), findsOneWidget);
    expect(find.text('Protected Dashboard'), findsNothing);
    await authChanges.close();
    await profileChanges.close();
  });
}

OccupierUser _profile(String uid, UserRole role) => OccupierUser(
  uid: uid,
  name: 'Test User',
  email: 'test@example.com',
  role: role,
);

Stream<OccupierUser?> _memberProfile(String uid) =>
    Stream.value(_profile(uid, UserRole.member));

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
  AppRoutes.branches: (_) =>
      const Scaffold(body: Text('Test route ${AppRoutes.branches}')),
  AppRoutes.desks: (_) =>
      const Scaffold(body: Text('Test route ${AppRoutes.desks}')),
  AppRoutes.meetingRooms: (_) =>
      const Scaffold(body: Text('Test route ${AppRoutes.meetingRooms}')),
  AppRoutes.bookings: (_) =>
      const Scaffold(body: Text('Test route ${AppRoutes.bookings}')),
  AppRoutes.occupancy: (_) =>
      const Scaffold(body: Text('Test route ${AppRoutes.occupancy}')),
  AppRoutes.myBookings: (_) =>
      const Scaffold(body: Text('Test route ${AppRoutes.myBookings}')),
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
  AppRoutes.walkInCheckIn: (_) =>
      const Text('Test route ${AppRoutes.walkInCheckIn}'),
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
