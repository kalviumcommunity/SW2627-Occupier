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
    await firestore.collection('occupancies').doc('occupancy-1').set(
      occupancyData(
        branchId: branchId,
        status: OccupancyStatus.active.name,
      ),
    );

    await firestore.collection('occupancies').doc('occupancy-2').set(
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
    await firestore.collection('occupancies').doc('occupancy-1').set(
      occupancyData(
        branchId: branchId,
        status: OccupancyStatus.active.name,
      ),
    );

    await firestore.collection('occupancies').doc('occupancy-2').set(
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
    await firestore.collection('occupancies').doc('occupancy-1').set(
      occupancyData(
        branchId: branchId,
        status: OccupancyStatus.active.name,
        userId: 'user-1',
      ),
    );

    await firestore.collection('occupancies').doc('occupancy-2').set(
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
      occupancyData(
        branchId: branchId,
        status: OccupancyStatus.active.name,
      ),
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
}
