import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/occupancy_repository.dart';
import 'package:mobile/models/occupancy.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late OccupancyRepository repository;

  const branchId = 'branch-test';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = OccupancyRepository(firestore: firestore);
  });

  Map<String, dynamic> occupancyData({
    required String branchId,
    required String status,
    String resourceId = 'desk-1',
    String userId = 'user-1',
  }) {
    final now = Timestamp.fromDate(DateTime(2026, 10, 16, 10));

    return {
      'branchId': branchId,
      'resourceId': resourceId,
      'resourceType': 'desk',
      'userId': userId,
      'bookingId': null,
      'status': status,
      'checkInTime': now,
      'checkOutTime': null,
      'source': OccupancySource.walkIn.name,
      'createdAt': now,
    };
  }

  test('emits active occupancies for all branches', () async {
    await firestore
        .collection('occupancies')
        .doc('occupancy-1')
        .set(
          occupancyData(
            branchId: branchId,
            status: OccupancyStatus.active.name,
          ),
        );

    await firestore
        .collection('occupancies')
        .doc('occupancy-2')
        .set(
          occupancyData(
            branchId: 'branch-other',
            status: OccupancyStatus.active.name,
            resourceId: 'desk-2',
          ),
        );

    final occupancies = await repository.watchActiveOccupancies().first;

    expect(occupancies, hasLength(2));
    expect(
      occupancies.every(
        (occupancy) => occupancy.status == OccupancyStatus.active,
      ),
      isTrue,
    );
  });

  test('filters active occupancies by branch', () async {
    await firestore
        .collection('occupancies')
        .doc('occupancy-1')
        .set(
          occupancyData(
            branchId: branchId,
            status: OccupancyStatus.active.name,
          ),
        );

    await firestore
        .collection('occupancies')
        .doc('occupancy-2')
        .set(
          occupancyData(
            branchId: 'branch-other',
            status: OccupancyStatus.active.name,
            resourceId: 'desk-2',
          ),
        );

    final occupancies = await repository
        .watchActiveOccupancies(branchId: branchId)
        .first;

    expect(occupancies, hasLength(1));
    expect(occupancies.first.branchId, branchId);
    expect(occupancies.first.occupancyId, 'occupancy-1');
  });

  test('filters active occupancies by user', () async {
    await firestore
        .collection('occupancies')
        .doc('occupancy-1')
        .set(
          occupancyData(
            branchId: branchId,
            status: OccupancyStatus.active.name,
            userId: 'user-1',
          ),
        );

    await firestore
        .collection('occupancies')
        .doc('occupancy-2')
        .set(
          occupancyData(
            branchId: branchId,
            status: OccupancyStatus.active.name,
            resourceId: 'desk-2',
            userId: 'user-2',
          ),
        );

    final occupancies = await repository
        .watchActiveOccupancies(userId: 'user-1')
        .first;

    expect(occupancies, hasLength(1));
    expect(occupancies.first.userId, 'user-1');
    expect(occupancies.first.occupancyId, 'occupancy-1');
  });

  test('stops emitting a record as active when it is completed', () async {
    final document = firestore.collection('occupancies').doc('occupancy-1');

    await document.set(
      occupancyData(branchId: branchId, status: OccupancyStatus.active.name),
    );

    final stream = repository.watchActiveOccupancies();
    final firstEmission = stream.first;

    final initialOccupancies = await firstEmission;
    expect(initialOccupancies, hasLength(1));

    await document.update({
      'status': OccupancyStatus.completed.name,
      'checkOutTime': Timestamp.fromDate(DateTime(2026, 10, 16, 11)),
    });

    final updatedOccupancies = await stream.first;
    expect(updatedOccupancies, isEmpty);
  });

  test('creates an active walk-in occupancy and occupies its desk', () async {
    await firestore.collection('branches').doc(branchId).set({
      'name': 'Test Branch',
    });
    await firestore
        .collection('branches')
        .doc(branchId)
        .collection('desks')
        .doc('desk-1')
        .set({'status': 'available'});

    final occupancyId = await repository.createWalkInOccupancy(
      branchId: branchId,
      resourceId: 'desk-1',
      resourceType: 'desk',
      customerName: '  Alex Customer ',
      customerPhone: ' +1 555 0100 ',
    );

    final resource = await firestore
        .collection('branches')
        .doc(branchId)
        .collection('desks')
        .doc('desk-1')
        .get();
    final occupancy = await firestore
        .collection('occupancies')
        .doc(occupancyId)
        .get();

    expect(resource.data()?['status'], 'occupied');
    expect(resource.data()?['activeOccupancyId'], occupancyId);
    expect(occupancy.data()?['occupancyId'], occupancyId);
    expect(occupancy.data()?['branchId'], branchId);
    expect(occupancy.data()?['resourceId'], 'desk-1');
    expect(occupancy.data()?['resourceType'], 'desk');
    expect(occupancy.data()?['source'], 'walkIn');
    expect(occupancy.data()?['status'], 'active');
    expect(occupancy.data()?['customerName'], 'Alex Customer');
    expect(occupancy.data()?['customerPhone'], '+1 555 0100');
    expect(occupancy.data()?['userId'], startsWith('walk-in-'));
    expect(occupancy.data()?['checkInTime'], isA<Timestamp>());
    expect(occupancy.data()?['checkOutTime'], isNull);
  });

  test('creates walk-in occupancy for a meeting room', () async {
    await firestore.collection('branches').doc(branchId).set({
      'name': 'Test Branch',
    });
    await firestore
        .collection('branches')
        .doc(branchId)
        .collection('rooms')
        .doc('room-1')
        .set({'status': 'available'});

    final occupancyId = await repository.createWalkInOccupancy(
      branchId: branchId,
      resourceId: 'room-1',
      resourceType: 'room',
      customerName: 'Alex Customer',
      customerPhone: '555-0100',
    );

    final room = await firestore
        .collection('branches')
        .doc(branchId)
        .collection('rooms')
        .doc('room-1')
        .get();
    final occupancy = await firestore
        .collection('occupancies')
        .doc(occupancyId)
        .get();

    expect(room.data()?['status'], 'occupied');
    expect(room.data()?['activeOccupancyId'], occupancyId);
    expect(occupancy.data()?['resourceType'], 'room');
    expect(occupancy.data()?['source'], 'walkIn');
  });

  test('checks out a walk-in and releases its desk atomically', () async {
    await firestore.collection('branches').doc(branchId).set({
      'name': 'Test Branch',
    });
    await firestore
        .collection('branches')
        .doc(branchId)
        .collection('desks')
        .doc('desk-1')
        .set({'status': 'available'});

    final occupancyId = await repository.createWalkInOccupancy(
      branchId: branchId,
      resourceId: 'desk-1',
      resourceType: 'desk',
      customerName: 'Alex Customer',
      customerPhone: '555-0100',
    );

    await repository.checkOut(occupancyId);

    final occupancy = await firestore
        .collection('occupancies')
        .doc(occupancyId)
        .get();
    final resource = await firestore
        .collection('branches')
        .doc(branchId)
        .collection('desks')
        .doc('desk-1')
        .get();

    expect(occupancy.data()?['status'], OccupancyStatus.completed.name);
    expect(occupancy.data()?['checkOutTime'], isA<Timestamp>());
    expect(resource.data()?['status'], 'available');
    expect(resource.data()?['activeOccupancyId'], isNull);
    expect(
      await repository.watchActiveOccupancies(branchId: branchId).first,
      isEmpty,
    );
  });

  test(
    'rejects repeated checkout without changing the available resource',
    () async {
      await firestore.collection('branches').doc(branchId).set({
        'name': 'Test Branch',
      });
      await firestore
          .collection('branches')
          .doc(branchId)
          .collection('desks')
          .doc('desk-1')
          .set({'status': 'available'});

      final occupancyId = await repository.createWalkInOccupancy(
        branchId: branchId,
        resourceId: 'desk-1',
        resourceType: 'desk',
        customerName: 'Alex Customer',
        customerPhone: '555-0100',
      );
      await repository.checkOut(occupancyId);

      await expectLater(
        repository.checkOut(occupancyId),
        throwsA(isA<StateError>()),
      );

      final resource = await firestore
          .collection('branches')
          .doc(branchId)
          .collection('desks')
          .doc('desk-1')
          .get();
      expect(resource.data()?['status'], 'available');
      expect(resource.data()?['activeOccupancyId'], isNull);
    },
  );

  test(
    'does not release a resource owned by another active occupancy',
    () async {
      await firestore.collection('branches').doc(branchId).set({
        'name': 'Test Branch',
      });
      await firestore
          .collection('branches')
          .doc(branchId)
          .collection('desks')
          .doc('desk-1')
          .set({'status': 'occupied', 'activeOccupancyId': 'other-occupancy'});
      await firestore
          .collection('occupancies')
          .doc('occupancy-1')
          .set(
            occupancyData(
              branchId: branchId,
              status: OccupancyStatus.active.name,
            ),
          );

      await expectLater(
        repository.checkOut('occupancy-1'),
        throwsA(isA<StateError>()),
      );

      final occupancy = await firestore
          .collection('occupancies')
          .doc('occupancy-1')
          .get();
      final resource = await firestore
          .collection('branches')
          .doc(branchId)
          .collection('desks')
          .doc('desk-1')
          .get();
      expect(occupancy.data()?['status'], OccupancyStatus.active.name);
      expect(resource.data()?['status'], 'occupied');
      expect(resource.data()?['activeOccupancyId'], 'other-occupancy');
    },
  );

  test('rejects a resource occupied before the transaction', () async {
    await firestore.collection('branches').doc(branchId).set({
      'name': 'Test Branch',
    });
    await firestore
        .collection('branches')
        .doc(branchId)
        .collection('desks')
        .doc('desk-1')
        .set({'status': 'occupied'});

    await expectLater(
      repository.createWalkInOccupancy(
        branchId: branchId,
        resourceId: 'desk-1',
        resourceType: 'desk',
        customerName: 'Alex Customer',
        customerPhone: '555-0100',
      ),
      throwsA(isA<StateError>()),
    );

    expect((await firestore.collection('occupancies').get()).docs, isEmpty);
  });
}
