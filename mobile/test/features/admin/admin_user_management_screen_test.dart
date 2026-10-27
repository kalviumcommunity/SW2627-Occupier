import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/admin_user_repository.dart';
import 'package:mobile/features/admin/admin_user_management_screen.dart';
import 'package:mobile/models/user.dart';

void main() {
  const member = OccupierUser(
    uid: 'member-1',
    name: 'Alice Member',
    email: 'alice@example.com',
    role: UserRole.member,
  );

  testWidgets('shows users and filters by name or email', (tester) async {
    final repository = _FakeAdminUserRepository(
      users: const [
        member,
        OccupierUser(
          uid: 'staff-1',
          name: 'Sam Staff',
          email: 'sam@example.com',
          role: UserRole.staff,
        ),
      ],
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Alice Member'), findsOneWidget);
    expect(find.text('alice@example.com\nRole: Member'), findsOneWidget);
    expect(find.text('Sam Staff'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'sam@');
    await tester.pumpAndSettle();

    expect(find.text('Sam Staff'), findsOneWidget);
    expect(find.text('Alice Member'), findsNothing);
  });

  testWidgets('shows loading and empty states', (tester) async {
    final controller = StreamController<List<OccupierUser>>();
    final repository = _FakeAdminUserRepository(stream: controller.stream);
    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller.add(const []);
    await tester.pumpAndSettle();
    expect(find.text('No registered users found.'), findsOneWidget);
    await controller.close();
  });

  testWidgets('shows an error and retry for permission-denied list reads', (
    tester,
  ) async {
    final repository = _FakeAdminUserRepository(
      stream: Stream.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      ),
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load registered users.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('requires confirmation before saving a role change', (
    tester,
  ) async {
    final repository = _FakeAdminUserRepository(users: const [member]);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Change role'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm role change'), findsOneWidget);
    expect(repository.updates, isEmpty);

    await tester.tap(find.byType(DropdownButtonFormField<UserRole>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save role'));
    await tester.pumpAndSettle();

    expect(repository.updates, [(userId: 'member-1', role: UserRole.staff)]);
    expect(
      find.text('Alice Member is now assigned the Staff role.'),
      findsOneWidget,
    );
  });

  testWidgets('shows role update permission failures', (tester) async {
    final repository = _FakeAdminUserRepository(
      users: const [member],
      updateError: FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ),
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Change role'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<UserRole>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save role'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Permission denied. Your administrator access may have changed.',
      ),
      findsOneWidget,
    );
  });
}

Widget _app(AdminUserRepository repository) {
  return MaterialApp(home: AdminUserManagementScreen(repository: repository));
}

class _FakeAdminUserRepository implements AdminUserRepository {
  _FakeAdminUserRepository({
    this.users = const [],
    this.stream,
    this.updateError,
  });

  List<OccupierUser> users;
  final Stream<List<OccupierUser>>? stream;
  final Object? updateError;
  final updates = <({String userId, UserRole role})>[];

  @override
  Stream<List<OccupierUser>> watchUsers() => stream ?? Stream.value(users);

  @override
  Future<void> updateUserRole({
    required String userId,
    required UserRole role,
  }) async {
    updates.add((userId: userId, role: role));
    if (updateError case final error?) throw error;
    users = [
      for (final user in users)
        if (user.uid == userId)
          OccupierUser(
            uid: user.uid,
            name: user.name,
            email: user.email,
            role: role,
          )
        else
          user,
    ];
  }
}
