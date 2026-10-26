import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/occupancy_repository.dart';
import 'package:mobile/core/services/resource_repository.dart';
import 'package:mobile/core/services/user_repository.dart';
import 'package:mobile/features/occupancy/walk_in_check_out_screen.dart';

void main() {
  testWidgets('does not expose checkout operations to a member', (
    tester,
  ) async {
    final firestore = await _seedFirestore(role: 'member');

    await tester.pumpWidget(
      MaterialApp(
        home: WalkInCheckOutScreen(
          currentUserId: () => 'staff-1',
          resourceRepository: ResourceRepository(firestore: firestore),
          occupancyRepository: OccupancyRepository(firestore: firestore),
          userRepository: UserRepository(
            firestore: firestore,
            currentUserId: () => 'staff-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Walk-in check-out is available to authorized staff only.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('walk-in-checkout-occupancy-1')),
      findsNothing,
    );
  });

  testWidgets('shows walk-in details and confirms checkout before submission', (
    tester,
  ) async {
    final firestore = await _seedFirestore(role: 'staff');
    final repository = _DelayedOccupancyRepository(firestore);

    await tester.pumpWidget(
      MaterialApp(
        home: WalkInCheckOutScreen(
          currentUserId: () => 'staff-1',
          resourceRepository: ResourceRepository(firestore: firestore),
          occupancyRepository: repository,
          userRepository: UserRepository(
            firestore: firestore,
            currentUserId: () => 'staff-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alex Customer'), findsOneWidget);
    expect(find.text('Contact: 555-0100'), findsOneWidget);
    expect(find.text('Resource: Desk · Desk 1 · Floor 1'), findsOneWidget);
    expect(find.textContaining('Checked in:'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('walk-in-checkout-occupancy-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirm check-out'), findsOneWidget);
    expect(repository.calls, 0);

    await tester.tap(find.byKey(const ValueKey('walk-in-checkout-confirm')));
    await tester.pump();
    expect(repository.calls, 1);
    expect(find.text('Checking out...'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('walk-in-checkout-occupancy-1')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repository.calls, 1);

    repository.completion.complete();
    await tester.pumpAndSettle();

    expect(find.text('Walk-in checked out successfully.'), findsOneWidget);
    expect(find.text('Alex Customer'), findsNothing);
  });

  testWidgets('shows checkout errors and permits retry', (tester) async {
    final firestore = await _seedFirestore(role: 'staff');
    final repository = _FailingOccupancyRepository(firestore);

    await tester.pumpWidget(
      MaterialApp(
        home: WalkInCheckOutScreen(
          currentUserId: () => 'staff-1',
          resourceRepository: ResourceRepository(firestore: firestore),
          occupancyRepository: repository,
          userRepository: UserRepository(
            firestore: firestore,
            currentUserId: () => 'staff-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('walk-in-checkout-occupancy-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('walk-in-checkout-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to check out walk-in: Checkout rejected.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('walk-in-checkout-occupancy-1')),
      findsOneWidget,
    );
    expect(repository.calls, 1);
  });
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
      .set({
        'name': 'Desk 1',
        'type': 'hotDesk',
        'floor': '1',
        'status': 'occupied',
        'activeOccupancyId': 'occupancy-1',
      });
  await firestore.collection('occupancies').doc('occupancy-1').set({
    'occupancyId': 'occupancy-1',
    'branchId': 'branch-1',
    'resourceId': 'desk-1',
    'resourceType': 'desk',
    'userId': 'walk-in-occupancy-1',
    'bookingId': null,
    'status': 'active',
    'checkInTime': Timestamp.fromDate(DateTime(2026, 10, 16, 10)),
    'checkOutTime': null,
    'source': 'walkIn',
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 16, 10)),
    'customerName': 'Alex Customer',
    'customerPhone': '555-0100',
  });
  return firestore;
}

class _DelayedOccupancyRepository extends OccupancyRepository {
  _DelayedOccupancyRepository(FakeFirebaseFirestore firestore)
    : super(firestore: firestore);

  final Completer<void> completion = Completer<void>();
  int calls = 0;

  @override
  Future<void> checkOut(String occupancyId) {
    calls++;
    return completion.future;
  }
}

class _FailingOccupancyRepository extends OccupancyRepository {
  _FailingOccupancyRepository(FakeFirebaseFirestore firestore)
    : super(firestore: firestore);

  int calls = 0;

  @override
  Future<void> checkOut(String occupancyId) async {
    calls++;
    throw StateError('Checkout rejected.');
  }
}
