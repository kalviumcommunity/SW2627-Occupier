import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/occupancy_repository.dart';
import 'package:mobile/core/services/resource_repository.dart';
import 'package:mobile/models/desk.dart';
import 'package:mobile/services/occupancy_service.dart';
import 'package:mobile/models/meeting_room.dart';
import 'package:mobile/models/occupancy.dart';

void main() {
  final service = OccupancyService();

  test('calculates occupancy and availability safely for zero capacity', () {
    expect(service.calculateOccupancyRate(occupied: 3, capacity: 4), 75);
    expect(service.calculateAvailable(occupied: 3, capacity: 4), 1);
    expect(service.calculateOccupancyRate(occupied: 0, capacity: 0), 0);
    expect(service.calculateAvailable(occupied: 5, capacity: 4), 0);
  });

  test(
    'calculates occupied, available, and percentage without double counting',
    () {
      const totalDeskUnits = 3;
      const totalRoomSeats = 7;
      const occupiedDeskUnits = 1;
      const occupiedRoomSeats = 4;

      const totalCapacity = totalDeskUnits + totalRoomSeats;
      const occupiedCapacity = occupiedDeskUnits + occupiedRoomSeats;

      expect(
        service.calculateAvailable(
          occupied: occupiedCapacity,
          capacity: totalCapacity,
        ),
        5,
      );

      expect(
        service.calculateOccupancyRate(
          occupied: occupiedCapacity,
          capacity: totalCapacity,
        ),
        50,
      );
    },
  );

  test(
    'returns zero percent and zero available capacity for empty branches',
    () {
      expect(service.calculateOccupancyRate(occupied: 0, capacity: 0), 0);
      expect(service.calculateAvailable(occupied: 0, capacity: 0), 0);
    },
  );

  test('clamps availability when occupancy exceeds capacity', () {
    expect(service.calculateAvailable(occupied: 4, capacity: 3), 0);
  });

  test(
    'calculates branch desk and room utilization without double counting',
    () {
      final summary = service.calculateBranchSummary(
        branchId: 'branch-1',
        desks: const [
          Desk(
            id: 'desk-available-1',
            name: 'Desk 1',
            type: 'hotDesk',
            floor: '1',
            status: DeskStatus.available,
          ),
          Desk(
            id: 'desk-available-2',
            name: 'Desk 2',
            type: 'hotDesk',
            floor: '1',
            status: DeskStatus.available,
          ),
          Desk(
            id: 'desk-occupied',
            name: 'Desk 3',
            type: 'hotDesk',
            floor: '1',
            status: DeskStatus.occupied,
          ),
          Desk(
            id: 'desk-maintenance',
            name: 'Desk 4',
            type: 'hotDesk',
            floor: '1',
            status: DeskStatus.maintenance,
          ),
        ],
        meetingRooms: const [
          MeetingRoom(
            id: 'room-available',
            name: 'Room 1',
            capacity: 4,
            floor: '1',
            amenities: [],
            status: MeetingRoomStatus.available,
          ),
          MeetingRoom(
            id: 'room-occupied',
            name: 'Room 2',
            capacity: 6,
            floor: '1',
            amenities: [],
            status: MeetingRoomStatus.occupied,
          ),
        ],
        activeOccupancies: [
          _occupancy('branch-1', 'desk', 'desk-occupied'),
          _occupancy('branch-1', 'desk', 'desk-occupied', id: 'duplicate'),
          _occupancy(
            'branch-1',
            'desk',
            'desk-available-1',
            status: OccupancyStatus.completed,
          ),
          _occupancy('branch-2', 'desk', 'other-branch-desk'),
        ],
      );

      expect(summary.totalResources, 6);
      expect(summary.occupiedResources, 2);
      expect(summary.availableResources, 3);
      expect(summary.unavailableResources, 1);
      expect(summary.unavailableDesks, 1);
      expect(summary.unavailableMeetingRooms, 0);
      expect(summary.availableDesks, 2);
      expect(summary.occupiedDesks, 1);
      expect(summary.availableMeetingRooms, 1);
      expect(summary.occupiedMeetingRooms, 1);
      expect(summary.totalCapacity, 13);
      expect(summary.occupiedCapacity, 7);
      expect(summary.availableCapacity, 6);
      expect(summary.occupancyRate, closeTo(53.846, 0.001));
      expect(summary.activeCheckIns, 1);
    },
  );

  test(
    'calculates network rate from aggregate capacity, not branch averages',
    () {
      final smallerBranch = service.calculateBranchSummary(
        branchId: 'small',
        desks: const [
          Desk(
            id: 'small-desk',
            name: 'Desk',
            type: 'hotDesk',
            floor: '1',
            status: DeskStatus.occupied,
          ),
        ],
        meetingRooms: const [],
        activeOccupancies: const [],
      );
      final largerBranch = service.calculateBranchSummary(
        branchId: 'large',
        desks: const [
          Desk(
            id: 'large-available',
            name: 'Available desk',
            type: 'hotDesk',
            floor: '1',
            status: DeskStatus.available,
          ),
          Desk(
            id: 'large-occupied',
            name: 'Occupied desk',
            type: 'hotDesk',
            floor: '1',
            status: DeskStatus.occupied,
          ),
          Desk(
            id: 'large-available-2',
            name: 'Available desk 2',
            type: 'hotDesk',
            floor: '1',
            status: DeskStatus.available,
          ),
        ],
        meetingRooms: const [],
        activeOccupancies: const [],
      );
      final network = service.calculateNetworkSummary([
        smallerBranch,
        largerBranch,
      ]);

      expect(smallerBranch.occupancyRate, 100);
      expect(largerBranch.occupancyRate, closeTo(33.333, 0.001));
      expect(network.totalBranches, 2);
      expect(network.totalResources, 4);
      expect(network.occupiedResources, 2);
      expect(network.availableResources, 2);
      expect(network.occupancyRate, 50);
    },
  );

  test('handles empty branches and zero-seat rooms safely', () {
    final emptyBranch = service.calculateBranchSummary(
      branchId: 'empty',
      desks: const [],
      meetingRooms: const [],
      activeOccupancies: const [],
    );
    final zeroSeatBranch = service.calculateBranchSummary(
      branchId: 'zero-seat',
      desks: const [],
      meetingRooms: const [
        MeetingRoom(
          id: 'zero-room',
          name: 'Room',
          capacity: 0,
          floor: '1',
          amenities: [],
          status: MeetingRoomStatus.available,
        ),
      ],
      activeOccupancies: const [],
    );

    expect(emptyBranch.totalResources, 0);
    expect(emptyBranch.occupancyRate, 0);
    expect(emptyBranch.availableCapacity, 0);
    expect(zeroSeatBranch.totalResources, 1);
    expect(zeroSeatBranch.totalCapacity, 0);
    expect(zeroSeatBranch.occupancyRate, 0);

    final network = service.calculateNetworkSummary([emptyBranch]);
    expect(network.totalBranches, 1);
    expect(network.totalCapacity, 0);
    expect(network.occupancyRate, 0);
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

Occupancy _occupancy(
  String branchId,
  String resourceType,
  String resourceId, {
  String id = 'occupancy',
  OccupancyStatus status = OccupancyStatus.active,
}) {
  final now = DateTime.utc(2026, 10, 31);
  return Occupancy(
    occupancyId: id,
    branchId: branchId,
    resourceId: resourceId,
    resourceType: resourceType,
    userId: 'user',
    status: status,
    checkInTime: now,
    source: OccupancySource.walkIn,
    createdAt: now,
  );
}
