import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/occupancy_repository.dart';
import 'package:mobile/core/services/resource_repository.dart';
import 'package:mobile/core/services/user_repository.dart';
import 'package:mobile/features/occupancy/walk_in_check_in_screen.dart';

void main() {
  testWidgets('does not expose walk-in registration to a member', (
    tester,
  ) async {
    final firestore = await _seedFirestore(role: 'member');
    final screen = WalkInCheckInScreen(
      currentUserId: () => 'staff-1',
      resourceRepository: ResourceRepository(firestore: firestore),
      occupancyRepository: OccupancyRepository(firestore: firestore),
      userRepository: UserRepository(
        firestore: firestore,
        currentUserId: () => 'staff-1',
      ),
    );

    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();

    expect(
      find.text('Walk-in check-in is available to authorized staff only.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('walk-in-submit')), findsNothing);
  });

  testWidgets('prevents duplicate submissions while a check-in is pending', (
    tester,
  ) async {
    final firestore = await _seedFirestore(role: 'staff');
    final delayedRepository = _DelayedOccupancyRepository();
    final screen = WalkInCheckInScreen(
      currentUserId: () => 'staff-1',
      resourceRepository: ResourceRepository(firestore: firestore),
      occupancyRepository: delayedRepository,
      userRepository: UserRepository(
        firestore: firestore,
        currentUserId: () => 'staff-1',
      ),
    );

    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('walk-in-branch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Branch').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('walk-in-resource-desk:desk-1')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('walk-in-customer-name')),
      'Alex Customer',
    );
    await tester.enterText(
      find.byKey(const ValueKey('walk-in-customer-phone')),
      '555-0100',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('walk-in-submit')));
    await tester.tap(find.byKey(const ValueKey('walk-in-submit')));
    await tester.pump();

    expect(delayedRepository.calls, 1);
    expect(find.text('Checking in...'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('walk-in-submit')));
    await tester.pump();
    expect(delayedRepository.calls, 1);

    delayedRepository.completion.complete('occupancy-1');
    await tester.pumpAndSettle();

    expect(find.text('Walk-in checked in successfully.'), findsOneWidget);
    expect(delayedRepository.calls, 1);
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
        'status': 'available',
      });
  return firestore;
}

class _DelayedOccupancyRepository extends OccupancyRepository {
  _DelayedOccupancyRepository() : super(firestore: FakeFirebaseFirestore());

  final Completer<String> completion = Completer<String>();
  int calls = 0;

  @override
  Future<String> createWalkInOccupancy({
    required String branchId,
    required String resourceId,
    required String resourceType,
    required String customerName,
    required String customerPhone,
  }) {
    calls++;
    return completion.future;
  }
}
