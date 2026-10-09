import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/resource_repository.dart';
import 'package:mobile/models/desk.dart';
import 'package:mobile/models/meeting_room.dart';

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
