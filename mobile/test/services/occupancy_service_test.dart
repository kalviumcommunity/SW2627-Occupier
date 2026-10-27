import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/occupancy_repository.dart';
import 'package:mobile/core/services/resource_repository.dart';
import 'package:mobile/models/desk.dart';
import 'package:mobile/services/occupancy_service.dart';

void main() {
  test('calculates occupancy and availability safely for zero capacity', () {
    final service = OccupancyService();

    expect(service.calculateOccupancyRate(occupied: 3, capacity: 4), 75);
    expect(service.calculateAvailable(occupied: 3, capacity: 4), 1);
    expect(service.calculateOccupancyRate(occupied: 0, capacity: 0), 0);
    expect(service.calculateAvailable(occupied: 5, capacity: 4), 0);
  });

  test(
    'resource status changes produce updated live occupancy values',
    () async {
      final firestore = FakeFirebaseFirestore();
      const branchId = 'branch-test';
      await firestore.collection('branches').doc(branchId).set({
        'name': 'Test',
      });
      await firestore
          .collection('branches')
          .doc(branchId)
          .collection('desks')
          .doc('desk-1')
          .set({'name': 'Desk 1', 'status': 'available'});

      final resources = ResourceRepository(firestore: firestore);
      final repository = OccupancyRepository(firestore: firestore);
      final service = OccupancyService();
      final ratesFuture = resources
          .watchDesks(branchId)
          .map(
            (desks) => service.calculateOccupancyRate(
              occupied: desks
                  .where((desk) => desk.status == DeskStatus.occupied)
                  .length,
              capacity: desks.length,
            ),
          )
          .take(2)
          .toList();

      await repository.createWalkInOccupancy(
        branchId: branchId,
        resourceId: 'desk-1',
        resourceType: 'desk',
        customerName: 'Alex Customer',
        customerPhone: '555-0100',
      );

      expect(await ratesFuture, [0, 100]);
    },
  );
}
