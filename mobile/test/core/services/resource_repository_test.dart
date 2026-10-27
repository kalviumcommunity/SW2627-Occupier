import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/resource_repository.dart';
import 'package:mobile/models/desk.dart';
import 'package:mobile/models/meeting_room.dart';
import 'package:mobile/models/branch.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ResourceRepository repository;

  const branchId = 'branch-test';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = ResourceRepository(firestore: firestore);
  });

  Future<void> createTestBranch() async {
    await firestore.collection('branches').doc(branchId).set({
      'name': 'Test Branch',
    });
  }

  group('Branch repository', () {
    const branch = Branch(
      name: 'Central Branch',
      address: '10 MG Road',
      city: 'Jaipur',
      contactNumber: '9876543210',
      totalDeskCapacity: 40,
      totalRoomCapacity: 6,
      openingTime: '09:00',
      closingTime: '18:00',
      status: BranchStatus.active,
    );

    test('creates and retrieves a branch', () async {
      final branchId = await repository.createBranch(branch);
      final savedBranch = await repository.getBranch(branchId);

      expect(savedBranch, isNotNull);
      expect(savedBranch!.id, branchId);
      expect(savedBranch.name, branch.name);
      expect(savedBranch.city, branch.city);
      expect(savedBranch.status, BranchStatus.active);
    });

    test('updates branch details and preserves createdAt', () async {
      final branchId = await repository.createBranch(branch);
      final document = firestore.collection('branches').doc(branchId);

      final createdAtBefore = (await document.get()).data()?['createdAt'];

      await repository.updateBranch(
        Branch(
          id: branchId,
          name: 'Updated Central Branch',
          address: branch.address,
          city: branch.city,
          contactNumber: branch.contactNumber,
          totalDeskCapacity: 50,
          totalRoomCapacity: branch.totalRoomCapacity,
          openingTime: branch.openingTime,
          closingTime: branch.closingTime,
          status: branch.status,
        ),
      );

      final updated = await repository.getBranch(branchId);
      final createdAtAfter = (await document.get()).data()?['createdAt'];

      expect(updated, isNotNull);
      expect(updated!.name, 'Updated Central Branch');
      expect(updated.totalDeskCapacity, 50);
      expect(createdAtAfter, createdAtBefore);
    });

    test(
      'activates and deactivates a branch without changing its details',
      () async {
        final branchId = await repository.createBranch(branch);

        await repository.updateBranchStatus(branchId, BranchStatus.inactive);

        var savedBranch = await repository.getBranch(branchId);

        expect(savedBranch!.status, BranchStatus.inactive);
        expect(savedBranch.name, branch.name);

        await repository.updateBranchStatus(branchId, BranchStatus.active);

        savedBranch = await repository.getBranch(branchId);

        expect(savedBranch!.status, BranchStatus.active);
        expect(savedBranch.name, branch.name);
      },
    );
  });

  group('Desk repository', () {
    test('creates and retrieves a desk', () async {
      await createTestBranch();

      final deskId = await repository.createDesk(
        branchId,
        const Desk(
          name: 'Desk 12',
          type: 'hot_desk',
          floor: '1',
          status: DeskStatus.available,
        ),
      );

      final desk = await repository.getDesk(branchId, deskId);

      expect(desk, isNotNull);
      expect(desk!.id, deskId);
      expect(desk.name, 'Desk 12');
      expect(desk.type, 'hot_desk');
      expect(desk.status, DeskStatus.available);
    });

    test('returns null for a missing desk', () async {
      final desk = await repository.getDesk(branchId, 'nonexistent-desk');

      expect(desk, isNull);
    });

    test('watches desks belonging to a branch', () async {
      await createTestBranch();

      await repository.createDesk(
        branchId,
        const Desk(
          name: 'Desk 5',
          type: 'dedicated',
          floor: '2',
          status: DeskStatus.available,
        ),
      );

      final desks = await repository.watchDesks(branchId).first;

      expect(desks, hasLength(1));
      expect(desks.first.name, 'Desk 5');
    });
  });

  group('Meeting room repository', () {
    test('creates and retrieves a meeting room', () async {
      await createTestBranch();

      final roomId = await repository.createMeetingRoom(
        branchId,
        const MeetingRoom(
          name: 'Conference Room A',
          capacity: 8,
          floor: '2',
          amenities: ['Projector', 'Whiteboard'],
          status: MeetingRoomStatus.available,
        ),
      );

      final room = await repository.getMeetingRoom(branchId, roomId);

      expect(room, isNotNull);
      expect(room!.id, roomId);
      expect(room.name, 'Conference Room A');
      expect(room.capacity, 8);
      expect(room.amenities, ['Projector', 'Whiteboard']);
      expect(room.status, MeetingRoomStatus.available);
    });

    test('returns null for a missing meeting room', () async {
      final room = await repository.getMeetingRoom(
        branchId,
        'nonexistent-room',
      );

      expect(room, isNull);
    });

    test('watches meeting rooms belonging to a branch', () async {
      await createTestBranch();

      await repository.createMeetingRoom(
        branchId,
        const MeetingRoom(
          name: 'Meeting Room B',
          capacity: 6,
          floor: '1',
          amenities: ['Screen'],
          status: MeetingRoomStatus.available,
        ),
      );

      final rooms = await repository.watchMeetingRooms(branchId).first;

      expect(rooms, hasLength(1));
      expect(rooms.first.name, 'Meeting Room B');
    });
  });
}
