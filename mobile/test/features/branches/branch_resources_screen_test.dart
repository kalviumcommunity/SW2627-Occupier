import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/resource_repository.dart';
import 'package:mobile/core/services/user_repository.dart';
import 'package:mobile/features/branches/branch_resources_screen.dart';
import 'package:mobile/models/branch.dart';
import 'package:mobile/models/desk.dart';
import 'package:mobile/models/meeting_room.dart';
import 'package:mobile/models/user.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ResourceRepository repository;
  late UserRepository userRepository;
  const uid = 'test-user';

  const testBranch = Branch(
    name: 'Central Branch',
    address: '10 MG Road',
    city: 'Jaipur',
    contactNumber: '9876543210',
    totalDeskCapacity: 20,
    totalRoomCapacity: 4,
    openingTime: '09:00',
    closingTime: '18:00',
    status: BranchStatus.active,
  );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = ResourceRepository(firestore: firestore);
    userRepository = UserRepository(
      firestore: firestore,
      currentUserId: () => uid,
    );
  });

  Future<void> seedProfile(UserRole role) async {
    await firestore.collection('users').doc(uid).set({
      'uid': uid,
      'name': 'Test User',
      'email': 'test@example.com',
      'role': role.name,
      'photoUrl': null,
      'createdAt': null,
    });
  }

  Future<Branch> createBranch() async {
    final id = await repository.createBranch(testBranch);
    return (await repository.getBranch(id))!;
  }

  Future<void> pumpResourceScreen(WidgetTester tester, Branch branch) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BranchResourcesScreen(
          branch: branch,
          repository: repository,
          userRepository: userRepository,
          currentUserId: () => uid,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('admin can mark an available desk as maintenance', (
    tester,
  ) async {
    await seedProfile(UserRole.admin);
    final branch = await createBranch();

    await repository.createDesk(
      branch.id,
      const Desk(
        name: 'Desk 1',
        type: 'hot_desk',
        floor: '1',
        status: DeskStatus.available,
      ),
    );

    await pumpResourceScreen(tester, branch);

    expect(find.text('Desk 1'), findsOneWidget);
    expect(find.byTooltip('Change status for Desk 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Change status for Desk 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maintenance'));
    await tester.pumpAndSettle();

    expect(find.text('Change desk status?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    final desks = await repository.watchDesks(branch.id).first;
    expect(desks.single.status, DeskStatus.maintenance);
    expect(find.text('Desk 1 status updated to Maintenance.'), findsOneWidget);
  });

  testWidgets('member cannot see resource status controls', (tester) async {
    await seedProfile(UserRole.member);
    final branch = await createBranch();

    await repository.createDesk(
      branch.id,
      const Desk(
        name: 'Desk 2',
        type: 'hot_desk',
        floor: '1',
        status: DeskStatus.available,
      ),
    );

    await repository.createMeetingRoom(
      branch.id,
      const MeetingRoom(
        name: 'Meeting Room A',
        capacity: 6,
        floor: '2',
        amenities: [],
        status: MeetingRoomStatus.available,
      ),
    );

    await pumpResourceScreen(tester, branch);

    expect(find.byTooltip('Change status for Desk 2'), findsNothing);

    await tester.tap(find.text('Meeting Rooms'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Change status for Meeting Room A'), findsNothing);
  });

  testWidgets('admin can deactivate a meeting room after confirmation', (
    tester,
  ) async {
    await seedProfile(UserRole.admin);
    final branch = await createBranch();

    await repository.createMeetingRoom(
      branch.id,
      const MeetingRoom(
        name: 'Meeting Room B',
        capacity: 8,
        floor: '2',
        amenities: ['Projector'],
        status: MeetingRoomStatus.available,
      ),
    );

    await pumpResourceScreen(tester, branch);

    await tester.tap(find.text('Meeting Rooms'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Change status for Meeting Room B'), findsOneWidget);

    await tester.tap(find.byTooltip('Change status for Meeting Room B'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inactive'));
    await tester.pumpAndSettle();

    expect(find.text('Change meeting room status?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    final rooms = await repository.watchMeetingRooms(branch.id).first;
    expect(rooms.single.status, MeetingRoomStatus.inactive);
    expect(
      find.text('Meeting Room B status updated to Inactive.'),
      findsOneWidget,
    );
  });

  testWidgets('occupied desk does not show status controls', (tester) async {
    await seedProfile(UserRole.admin);
    final branch = await createBranch();

    await repository.createDesk(
      branch.id,
      const Desk(
        name: 'Occupied Desk',
        type: 'dedicated',
        floor: '1',
        status: DeskStatus.occupied,
        activeOccupancyId: 'active-occupancy',
      ),
    );

    await pumpResourceScreen(tester, branch);

    expect(find.text('Occupied Desk'), findsOneWidget);
    expect(find.byTooltip('Change status for Occupied Desk'), findsNothing);
  });
}
