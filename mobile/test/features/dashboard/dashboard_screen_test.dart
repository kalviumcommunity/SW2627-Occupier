import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/constants/app_routes.dart';
import 'package:mobile/core/services/occupancy_repository.dart';
import 'package:mobile/core/services/resource_repository.dart';
import 'package:mobile/core/services/user_repository.dart';
import 'package:mobile/features/dashboard/dashboard_screen.dart';
import 'package:mobile/models/branch.dart';
import 'package:mobile/models/desk.dart';
import 'package:mobile/models/meeting_room.dart';
import 'package:mobile/models/user.dart';

void main() {
  testWidgets('shows a loading state while branches are loading', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedDashboard(firestore, role: UserRole.admin);
    final branches = StreamController<List<Branch>>();

    await tester.pumpWidget(
      _app(
        firestore,
        uid: 'admin-1',
        resourceRepository: _PendingBranchesRepository(
          firestore,
          branches.stream,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Occupancy Dashboard'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    branches.add(const []);
    await tester.pumpAndSettle();
    expect(find.text('No active branches found.'), findsOneWidget);
    await branches.close();
  });

  testWidgets('administrators see network totals and existing shortcuts', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedDashboard(firestore, role: UserRole.admin);

    await tester.pumpWidget(_app(firestore, uid: 'admin-1'));
    await tester.pumpAndSettle();

    expect(find.text('Network Overview'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('71.4%'), findsOneWidget);
    expect(find.byTooltip('Walk-in check-in'), findsOneWidget);
    expect(find.byTooltip('Active walk-ins'), findsOneWidget);
    expect(find.byTooltip('User management'), findsOneWidget);
    expect(find.byTooltip('My Bookings'), findsOneWidget);
    expect(find.text('Branch Occupancy', skipOffstage: false), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('North Branch'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('North Branch', skipOffstage: false), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('South Branch'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('South Branch', skipOffstage: false), findsOneWidget);
  });

  for (final role in [UserRole.branchManager, UserRole.staff]) {
    testWidgets('$role sees only assigned branch occupancy', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final uid = role == UserRole.staff ? 'staff-1' : 'manager-1';
      await _seedDashboard(firestore, role: role, uid: uid);

      await tester.pumpWidget(_app(firestore, uid: uid));
      await tester.pumpAndSettle();

      expect(find.text('Branch Overview'), findsOneWidget);
      expect(find.text('Your branches', skipOffstage: false), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('North Branch'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('North Branch', skipOffstage: false), findsOneWidget);
      expect(find.text('South Branch', skipOffstage: false), findsNothing);
      expect(find.text('Network Overview'), findsNothing);
    });
  }

  testWidgets('members see no occupancy data and retain booking navigation', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedDashboard(firestore, role: UserRole.member, uid: 'member-1');

    await tester.pumpWidget(_app(firestore, uid: 'member-1'));
    await tester.pumpAndSettle();

    expect(find.text('North Branch'), findsNothing);
    expect(find.text('South Branch'), findsNothing);
    expect(find.text('Network Overview'), findsNothing);
    expect(
      find.textContaining('Occupancy information is available'),
      findsOneWidget,
    );
    expect(find.byTooltip('My Bookings'), findsOneWidget);

    await tester.tap(find.byTooltip('My Bookings'));
    await tester.pumpAndSettle();
    expect(find.text('Bookings destination'), findsOneWidget);
  });

  testWidgets('dashboard refreshes when a resource changes status', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedDashboard(firestore, role: UserRole.admin);

    await tester.pumpWidget(_app(firestore, uid: 'admin-1'));
    await tester.pumpAndSettle();
    expect(find.text('71.4%'), findsOneWidget);

    await firestore
        .collection('branches')
        .doc('south')
        .collection('desks')
        .doc('desk-south')
        .update({'status': DeskStatus.occupied.name});
    await tester.pumpAndSettle();

    expect(find.text('85.7%'), findsOneWidget);
  });

  testWidgets('dashboard refreshes after check-in and check-out', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedDashboard(firestore, role: UserRole.admin);
    final occupancyRepository = OccupancyRepository(firestore: firestore);

    await tester.pumpWidget(_app(firestore, uid: 'admin-1'));
    await tester.pumpAndSettle();
    final activeCheckInCard = find
        .ancestor(
          of: find.text('Active check-ins'),
          matching: find.byType(Card),
        )
        .first;
    expect(
      find.descendant(of: activeCheckInCard, matching: find.text('0')),
      findsOneWidget,
    );

    final occupancyId = await occupancyRepository.createWalkInOccupancy(
      branchId: 'south',
      resourceId: 'desk-south',
      resourceType: 'desk',
      customerName: 'Walk-in Customer',
      customerPhone: '555-0100',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: activeCheckInCard, matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('85.7%'), findsOneWidget);

    await occupancyRepository.checkOut(occupancyId);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: activeCheckInCard, matching: find.text('0')),
      findsOneWidget,
    );
    expect(find.text('71.4%'), findsOneWidget);
  });

  testWidgets('shows an error and retry action when branches fail to load', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedDashboard(firestore, role: UserRole.admin);
    final resourceRepository = _FailingBranchesRepository(firestore);

    await tester.pumpWidget(
      _app(firestore, uid: 'admin-1', resourceRepository: resourceRepository),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to load branches from Firestore.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows an error when live resource streams fail', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _seedDashboard(firestore, role: UserRole.admin);
    final resourceRepository = _FailingDeskRepository(firestore);

    await tester.pumpWidget(
      _app(firestore, uid: 'admin-1', resourceRepository: resourceRepository),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unable to load live occupancy data.'), findsOneWidget);
  });
}

Widget _app(
  FakeFirebaseFirestore firestore, {
  required String uid,
  ResourceRepository? resourceRepository,
}) {
  return MaterialApp(
    home: DashboardScreen(
      currentUserId: () => uid,
      userRepository: UserRepository(
        firestore: firestore,
        currentUserId: () => uid,
      ),
      resourceRepository:
          resourceRepository ?? ResourceRepository(firestore: firestore),
      occupancyRepository: OccupancyRepository(firestore: firestore),
    ),
    routes: {
      AppRoutes.myBookings: (_) =>
          const Scaffold(body: Text('Bookings destination')),
    },
  );
}

Future<void> _seedDashboard(
  FakeFirebaseFirestore firestore, {
  required UserRole role,
  String uid = 'admin-1',
}) async {
  await firestore.collection('users').doc(uid).set({
    'uid': uid,
    'name': 'Dashboard User',
    'email': 'dashboard@example.com',
    'role': role.name,
  });

  await firestore.collection('branches').doc('north').set({
    'name': 'North Branch',
    'address': '1 Main Street',
    'city': 'North City',
    'contactNumber': '123456789',
    'totalDeskCapacity': 2,
    'totalRoomCapacity': 1,
    'openingTime': '09:00',
    'closingTime': '18:00',
    'status': BranchStatus.active.name,
    'managerUid': 'manager-1',
    'staffUids': ['staff-1'],
  });
  await firestore.collection('branches').doc('south').set({
    'name': 'South Branch',
    'address': '2 Main Street',
    'city': 'South City',
    'contactNumber': '123456789',
    'totalDeskCapacity': 1,
    'totalRoomCapacity': 0,
    'openingTime': '09:00',
    'closingTime': '18:00',
    'status': BranchStatus.active.name,
    'managerUid': 'manager-2',
    'staffUids': [],
  });

  final north = firestore.collection('branches').doc('north');
  await north.collection('desks').doc('desk-occupied').set({
    'name': 'Desk 1',
    'type': 'hotDesk',
    'floor': '1',
    'status': DeskStatus.occupied.name,
  });
  await north.collection('desks').doc('desk-available').set({
    'name': 'Desk 2',
    'type': 'hotDesk',
    'floor': '1',
    'status': DeskStatus.available.name,
  });
  await north.collection('rooms').doc('room-occupied').set({
    'name': 'Meeting room',
    'capacity': 4,
    'floor': '1',
    'amenities': <String>[],
    'status': MeetingRoomStatus.occupied.name,
  });

  await firestore
      .collection('branches')
      .doc('south')
      .collection('desks')
      .doc('desk-south')
      .set({
        'name': 'South desk',
        'type': 'hotDesk',
        'floor': '1',
        'status': DeskStatus.available.name,
      });
}

class _FailingBranchesRepository extends ResourceRepository {
  _FailingBranchesRepository(FakeFirebaseFirestore firestore)
    : super(firestore: firestore);

  @override
  Stream<List<Branch>> watchBranches() =>
      Stream.error(StateError('Branch listener failed.'));
}

class _PendingBranchesRepository extends ResourceRepository {
  _PendingBranchesRepository(
    FakeFirebaseFirestore firestore,
    this.branchesStream,
  ) : super(firestore: firestore);

  final Stream<List<Branch>> branchesStream;

  @override
  Stream<List<Branch>> watchBranches() => branchesStream;
}

class _FailingDeskRepository extends ResourceRepository {
  _FailingDeskRepository(FakeFirebaseFirestore firestore)
    : super(firestore: firestore);

  @override
  Stream<List<Desk>> watchDesks(String branchId) =>
      Stream.error(StateError('Desk listener failed.'));
}
