import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/resource_repository.dart';
import 'package:mobile/core/services/user_repository.dart';
import 'package:mobile/features/branches/branches_screen.dart';
import 'package:mobile/models/branch.dart';
import 'package:mobile/models/user.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ResourceRepository repository;
  late UserRepository userRepository;
  late String uid;

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

  setUp(() {
    uid = 'test-user';
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

  Future<void> pumpBranchesScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BranchesScreen(
          repository: repository,
          userRepository: userRepository,
          currentUserId: () => uid,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('admin sees branch management controls', (tester) async {
    await seedProfile(UserRole.admin);
    await repository.createBranch(branch);

    await pumpBranchesScreen(tester);

    expect(find.text('Central Branch'), findsOneWidget);
    expect(find.byTooltip('Create branch'), findsOneWidget);
    expect(find.byTooltip('Manage Central Branch'), findsOneWidget);
  });

  testWidgets('member can view branches but cannot manage them', (
    tester,
  ) async {
    await seedProfile(UserRole.member);
    await repository.createBranch(branch);

    await pumpBranchesScreen(tester);

    expect(find.text('Central Branch'), findsOneWidget);
    expect(find.byTooltip('Create branch'), findsNothing);
    expect(find.byTooltip('Manage Central Branch'), findsNothing);
  });

  testWidgets('branch form validates required fields', (tester) async {
    await seedProfile(UserRole.admin);
    await pumpBranchesScreen(tester);

    await tester.tap(find.byTooltip('Create branch'));
    await tester.pumpAndSettle();

    expect(find.text('Create branch'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilledButton, 'Create branch'));
    await tester.pumpAndSettle();

    expect(find.text('Branch name is required.'), findsOneWidget);
    expect(find.text('Address is required.'), findsOneWidget);
    expect(find.text('City is required.'), findsOneWidget);
    expect(find.text('Contact number is required.'), findsOneWidget);
  });

  testWidgets('admin can deactivate a branch after confirmation', (
    tester,
  ) async {
    await seedProfile(UserRole.admin);
    final branchId = await repository.createBranch(branch);

    await pumpBranchesScreen(tester);

    await tester.tap(find.byTooltip('Manage Central Branch'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deactivate branch'));
    await tester.pumpAndSettle();

    expect(find.text('Deactivate branch?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();

    final savedBranch = await repository.getBranch(branchId);

    expect(savedBranch, isNotNull);
    expect(savedBranch!.status, BranchStatus.inactive);
    expect(find.text('Branch deactivated successfully.'), findsOneWidget);
  });
}
