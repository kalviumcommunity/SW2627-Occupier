import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/occupancy_repository.dart';
import 'package:mobile/core/services/resource_repository.dart';
import 'package:mobile/core/services/user_repository.dart';
import 'package:mobile/features/occupancy/occupancy_management_screen.dart';

void main() {
  testWidgets('does not expose active walk-ins to a member', (tester) async {
    final firestore = await _seedFirestore(role: 'member');
    await _seedWalkIn(firestore, occupancyId: 'walk-in-1');

    await tester.pumpWidget(MaterialApp(home: _screen(firestore)));
    await tester.pumpAndSettle();

    expect(
      find.text('Active walk-ins are available to authorized staff only.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('walk-in-checkout-walk-in-1')),
      findsNothing,
    );
  });

  testWidgets('assigned staff checks out a walk-in and releases its desk', (
    tester,
  ) async {
    final firestore = await _seedFirestore(role: 'staff');
    await _seedWalkIn(firestore, occupancyId: 'walk-in-1');

    await tester.pumpWidget(MaterialApp(home: _screen(firestore)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('active-walk-in-walk-in-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('walk-in-checkout-walk-in-1')));
    await tester.pumpAndSettle();

    expect(find.text('Alex Customer'), findsNothing);
    expect(
      find.text('Walk-in checked out. Resource is now available.'),
      findsOneWidget,
    );
    expect(
      (await firestore
              .collection('branches')
              .doc('branch-1')
              .collection('desks')
              .doc('desk-1')
              .get())
          .data()?['status'],
      'available',
    );
  });

  testWidgets('staff only receive active walk-ins from assigned branches', (
    tester,
  ) async {
    final firestore = await _seedFirestore(role: 'staff');
    await _seedWalkIn(firestore, occupancyId: 'assigned-walk-in');
    await firestore.collection('branches').doc('branch-2').set({
      'name': 'Other Branch',
      'status': 'active',
      'managerUid': null,
      'staffUids': <String>[],
    });
    await _seedWalkIn(
      firestore,
      occupancyId: 'unassigned-walk-in',
      branchId: 'branch-2',
    );

    await tester.pumpWidget(MaterialApp(home: _screen(firestore)));
    await tester.pumpAndSettle();

    expect(find.text('Alex Customer'), findsOneWidget);
    expect(find.text('Other Customer'), findsNothing);
  });

  testWidgets('prevents duplicate checkout while the request is pending', (
    tester,
  ) async {
    final firestore = await _seedFirestore(role: 'staff');
    await _seedWalkIn(firestore, occupancyId: 'walk-in-1');
    final repository = _DelayedCheckoutRepository(firestore);

    await tester.pumpWidget(
      MaterialApp(home: _screen(firestore, occupancyRepository: repository)),
    );
    await tester.pumpAndSettle();

    final checkoutButton = find.byKey(
      const ValueKey('walk-in-checkout-walk-in-1'),
    );
    await tester.tap(checkoutButton);
    await tester.pump();

    expect(repository.calls, 1);
    expect(find.text('Checking out...'), findsOneWidget);

    await tester.tap(checkoutButton);
    await tester.pump();
    expect(repository.calls, 1);

    repository.completion.complete();
    await tester.pumpAndSettle();
    expect(find.text('Alex Customer'), findsNothing);
  });

  testWidgets('shows checkout failures to staff', (tester) async {
    final firestore = await _seedFirestore(role: 'staff');
    await _seedWalkIn(firestore, occupancyId: 'walk-in-1');
    final repository = _FailingCheckoutRepository(firestore);

    await tester.pumpWidget(
      MaterialApp(home: _screen(firestore, occupancyRepository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('walk-in-checkout-walk-in-1')));
    await tester.pumpAndSettle();

    expect(find.text('This occupancy is not active.'), findsOneWidget);
    expect(find.text('Alex Customer'), findsOneWidget);
  });
}

Widget _screen(
  FakeFirebaseFirestore firestore, {
  OccupancyRepository? occupancyRepository,
}) {
  return OccupancyManagementScreen(
    currentUserId: () => 'staff-1',
    resourceRepository: ResourceRepository(firestore: firestore),
    occupancyRepository:
        occupancyRepository ?? OccupancyRepository(firestore: firestore),
    userRepository: UserRepository(
      firestore: firestore,
      currentUserId: () => 'staff-1',
    ),
  );
}

Future<FakeFirebaseFirestore> _seedFirestore({required String role}) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc('staff-1').set({
    'uid': 'staff-1',
    'name': 'Branch Staff',
    'email': 'staff@example.com',
    'role': role,
  });
  await firestore.collection('branches').doc('branch-1').set({
    'name': 'Test Branch',
    'address': '1 Example Street',
    'city': 'Example City',
    'contactNumber': '5550100',
    'totalDeskCapacity': 1,
    'totalRoomCapacity': 0,
    'openingTime': '09:00',
    'closingTime': '18:00',
    'status': 'active',
    'managerUid': null,
    'staffUids': ['staff-1'],
  });
  await firestore
      .collection('branches')
      .doc('branch-1')
      .collection('desks')
      .doc('desk-1')
      .set({'name': 'Desk 1', 'status': 'occupied'});
  return firestore;
}

Future<void> _seedWalkIn(
  FakeFirebaseFirestore firestore, {
  required String occupancyId,
  String branchId = 'branch-1',
}) async {
  final now = DateTime(2026, 10, 16, 10);
  await firestore.collection('occupancies').doc(occupancyId).set({
    'occupancyId': occupancyId,
    'branchId': branchId,
    'resourceId': 'desk-1',
    'resourceType': 'desk',
    'userId': 'walk-in-$occupancyId',
    'bookingId': null,
    'status': 'active',
    'checkInTime': now,
    'checkOutTime': null,
    'source': 'walkIn',
    'createdAt': now,
    'customerName': branchId == 'branch-1' ? 'Alex Customer' : 'Other Customer',
    'customerPhone': '555-0100',
  });
}

class _DelayedCheckoutRepository extends OccupancyRepository {
  _DelayedCheckoutRepository(FakeFirebaseFirestore firestore)
    : super(firestore: firestore);

  final Completer<void> completion = Completer<void>();
  int calls = 0;

  @override
  Future<void> checkOut(String occupancyId) async {
    calls++;
    await completion.future;
    await super.checkOut(occupancyId);
  }
}

class _FailingCheckoutRepository extends OccupancyRepository {
  _FailingCheckoutRepository(FakeFirebaseFirestore firestore)
    : super(firestore: firestore);

  @override
  Future<void> checkOut(String occupancyId) {
    return Future<void>.error(StateError('This occupancy is not active.'));
  }
}
