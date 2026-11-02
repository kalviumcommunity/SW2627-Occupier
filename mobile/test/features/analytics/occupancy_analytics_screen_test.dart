import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/occupancy_repository.dart';
import 'package:mobile/core/services/resource_repository.dart';
import 'package:mobile/core/services/user_repository.dart';
import 'package:mobile/features/analytics/occupancy_analytics_screen.dart';
import 'package:mobile/models/occupancy.dart';
import 'package:mobile/models/user.dart';

void main() {
  testWidgets('shows a loading state while historical records load', (
    tester,
  ) async {
    final firestore = await _seed(role: UserRole.staff);
    final repository = _PendingAnalyticsRepository(firestore);

    await tester.pumpWidget(_app(firestore, repository));
    await tester.pump();

    expect(find.text('Occupancy Analytics'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.completion.complete(const []);
    await tester.pumpAndSettle();
    expect(
      find.text('No occupancy sessions in this reporting period.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a recoverable error when historical loading fails', (
    tester,
  ) async {
    final firestore = await _seed(role: UserRole.staff);

    await tester.pumpWidget(
      _app(firestore, _FailingAnalyticsRepository(firestore)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to load historical occupancy data.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows empty analytics state when the period has no sessions', (
    tester,
  ) async {
    final firestore = await _seed(role: UserRole.staff);

    await tester.pumpWidget(
      _app(firestore, _RecordingAnalyticsRepository(firestore)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No occupancy sessions in this reporting period.'),
      findsOneWidget,
    );
  });

  testWidgets('staff only query assigned branch and can switch periods', (
    tester,
  ) async {
    final firestore = await _seed(
      role: UserRole.staff,
      extraBranch: true,
      secondAssignedBranch: true,
    );
    final repository = _RecordingAnalyticsRepository(firestore);

    await tester.pumpWidget(_app(firestore, repository));
    await tester.pumpAndSettle();

    expect(repository.branchIds, ['assigned', 'assigned-2']);
    expect(find.byType(DropdownButtonFormField<String?>), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    expect(find.text('Assigned Branch'), findsOneWidget);
    expect(find.text('Second Assigned Branch'), findsOneWidget);
    expect(find.text('Private Branch'), findsNothing);
    expect(find.text('All branches (network)'), findsNothing);
    await tester.tap(find.text('Second Assigned Branch'));
    await tester.pumpAndSettle();
    expect(repository.branchIds.last, 'assigned-2');

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(repository.calls, 4);
    expect(repository.branchIds, [
      'assigned',
      'assigned-2',
      'assigned-2',
      'assigned-2',
    ]);
  });

  testWidgets('admin requests network totals and can select a branch', (
    tester,
  ) async {
    final firestore = await _seed(role: UserRole.admin, extraBranch: true);
    final repository = _RecordingAnalyticsRepository(firestore);

    await tester.pumpWidget(_app(firestore, repository));
    await tester.pumpAndSettle();

    expect(repository.branchIds, [null]);
    expect(find.text('All branches (network)'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assigned Branch').last);
    await tester.pumpAndSettle();

    expect(repository.branchIds, [null, 'assigned']);
  });

  testWidgets('members are denied without querying occupancy history', (
    tester,
  ) async {
    final firestore = await _seed(role: UserRole.member);
    final repository = _RecordingAnalyticsRepository(firestore);

    await tester.pumpWidget(_app(firestore, repository));
    await tester.pumpAndSettle();

    expect(
      find.text('Historical occupancy analytics are for staff only.'),
      findsOneWidget,
    );
    expect(repository.calls, 0);
  });

  testWidgets('renders supported metrics and explains capacity limitations', (
    tester,
  ) async {
    final firestore = await _seed(role: UserRole.admin);
    final repository = _RecordingAnalyticsRepository(
      firestore,
      records: [
        _occupancy(
          id: 'desk-session',
          branch: 'assigned',
          type: 'desk',
          start: DateTime(2026, 10, 15, 10),
          end: DateTime(2026, 10, 15, 11),
        ),
        _occupancy(
          id: 'room-session',
          branch: 'assigned',
          type: 'room',
          start: DateTime(2026, 10, 15, 10),
          end: DateTime(2026, 10, 15, 12),
        ),
      ],
    );
    await tester.pumpWidget(
      _app(firestore, repository, clock: () => DateTime(2026, 10, 15, 15)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total sessions'), findsOneWidget);
    final totalSessionsCard = find.ancestor(
      of: find.text('Total sessions'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: totalSessionsCard, matching: find.text('2')),
      findsOneWidget,
    );
    expect(find.text('3.0'), findsOneWidget);
    expect(find.textContaining('not occupied seat-hours'), findsOneWidget);
    expect(
      find.textContaining('Historical capacity snapshots'),
      findsOneWidget,
    );
    expect(find.text('Sessions by hour'), findsOneWidget);
    expect(find.textContaining('555'), findsNothing);
  });
}

Widget _app(
  FakeFirebaseFirestore firestore,
  _RecordingAnalyticsRepository repository, {
  DateTime Function()? clock,
}) {
  return MaterialApp(
    home: OccupancyAnalyticsScreen(
      currentUserId: () => 'user-1',
      userRepository: UserRepository(
        firestore: firestore,
        currentUserId: () => 'user-1',
      ),
      resourceRepository: ResourceRepository(firestore: firestore),
      occupancyRepository: repository,
      clock: clock ?? () => DateTime(2026, 10, 15, 15),
    ),
  );
}

Future<FakeFirebaseFirestore> _seed({
  required UserRole role,
  bool extraBranch = false,
  bool secondAssignedBranch = false,
}) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc('user-1').set({
    'uid': 'user-1',
    'name': 'Staff User',
    'email': 'staff@example.com',
    'role': role.name,
  });
  await firestore.collection('branches').doc('assigned').set({
    'name': 'Assigned Branch',
    'address': 'Test Street',
    'city': 'Test City',
    'contactNumber': '5550100',
    'totalDeskCapacity': 1,
    'totalRoomCapacity': 0,
    'openingTime': '09:00',
    'closingTime': '18:00',
    'status': 'active',
    'managerUid': null,
    'staffUids': ['user-1'],
  });
  if (secondAssignedBranch) {
    await firestore.collection('branches').doc('assigned-2').set({
      'name': 'Second Assigned Branch',
      'address': 'Second Street',
      'city': 'Second City',
      'contactNumber': '5550102',
      'totalDeskCapacity': 1,
      'totalRoomCapacity': 0,
      'openingTime': '09:00',
      'closingTime': '18:00',
      'status': 'active',
      'managerUid': null,
      'staffUids': ['user-1'],
    });
  }
  if (extraBranch) {
    await firestore.collection('branches').doc('private').set({
      'name': 'Private Branch',
      'address': 'Private Street',
      'city': 'Private City',
      'contactNumber': '5550101',
      'totalDeskCapacity': 1,
      'totalRoomCapacity': 0,
      'openingTime': '09:00',
      'closingTime': '18:00',
      'status': 'active',
      'managerUid': 'someone-else',
      'staffUids': <String>[],
    });
  }
  return firestore;
}

Occupancy _occupancy({
  required String id,
  required String branch,
  required String type,
  required DateTime start,
  required DateTime end,
}) => Occupancy(
  occupancyId: id,
  branchId: branch,
  resourceId: '$type-1',
  resourceType: type,
  userId: 'private-customer-id',
  status: OccupancyStatus.completed,
  checkInTime: start,
  checkOutTime: end,
  source: OccupancySource.walkIn,
  createdAt: start,
  customerName: 'Private Customer',
  customerPhone: '5550100',
);

class _RecordingAnalyticsRepository extends OccupancyRepository {
  _RecordingAnalyticsRepository(
    FakeFirebaseFirestore firestore, {
    this.records = const [],
  }) : super(firestore: firestore);

  final List<Occupancy> records;
  final List<String?> branchIds = [];

  int get calls => branchIds.length;

  @override
  Future<List<Occupancy>> fetchHistoricalOccupancies({
    required DateTime start,
    required DateTime end,
    String? branchId,
    int pageSize = 200,
  }) async {
    branchIds.add(branchId);
    return records;
  }
}

class _PendingAnalyticsRepository extends _RecordingAnalyticsRepository {
  _PendingAnalyticsRepository(super.firestore);

  final Completer<List<Occupancy>> completion = Completer<List<Occupancy>>();

  @override
  Future<List<Occupancy>> fetchHistoricalOccupancies({
    required DateTime start,
    required DateTime end,
    String? branchId,
    int pageSize = 200,
  }) {
    branchIds.add(branchId);
    return completion.future;
  }
}

class _FailingAnalyticsRepository extends _RecordingAnalyticsRepository {
  _FailingAnalyticsRepository(super.firestore);

  @override
  Future<List<Occupancy>> fetchHistoricalOccupancies({
    required DateTime start,
    required DateTime end,
    String? branchId,
    int pageSize = 200,
  }) => Future.error(StateError('Query failed.'));
}
